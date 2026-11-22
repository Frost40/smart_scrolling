"""The owner's upload tool. How to write content: docs/CONTENT_FORMAT.md.

    python tools/content/upload.py topics                    upload tools/content/topics.json
    python tools/content/upload.py <folder> [--dry-run]      upload one source folder, or a folder of source folders
    python tools/content/upload.py purge-samples [--dry-run] delete every is_sample source with its rows and files
    python tools/content/upload.py requests [--done <id>]    list the open to-dos, or mark one done

Uses SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from the root .env. Standard library only.
"""

import datetime
import hashlib
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

SLUG = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KINDS = {"book", "paper", "news", "other"}
STATUSES = {"draft", "published", "hidden"}
LEVELS = {"intro", "intermediate", "advanced"}
FORMATS = {"concept", "quote", "news", "research", "myth", "image", "video", "audio"}
TYPES = {"flashcard", "multiple_choice", "true_false", "ordering", "matching"}
DETAILS = {
    "book": ("book_details", {"isbn", "publisher", "edition", "pages"}),
    "paper": ("paper_details", {"doi", "journal", "paper_status"}),
    "news": ("news_details", {"newspaper", "show_until"}),
}
# role -> (allowed extensions, bucket name of the file)
FILES = {
    "cover": ({".jpg", ".jpeg", ".png", ".webp"}, "cover"),
    "original": ({".pdf", ".epub", ".html", ".txt"}, "original"),
    "text": ({".txt"}, "text"),
    "media": ({".webp", ".jpg", ".jpeg", ".png", ".mp4", ".m4a", ".mp3", ".wav"}, None),
    "poster": ({".jpg", ".jpeg", ".png", ".webp"}, "poster"),
    "captions": ({".vtt"}, "captions"),
}
MEDIA_NAME = {".mp4": "video", ".m4a": "audio", ".mp3": "audio", ".wav": "audio"}
SOURCE_FIELDS = ["kind", "title", "authors", "published_on", "language", "link", "description", "status", "is_sample"]
CARD_FIELDS = ["format", "title", "front", "back", "location", "position", "level", "language", "speaker",
               "media_alt", "transcript", "duration_seconds", "status"]
PRACTICE_FIELDS = ["type", "prompt", "answer", "choices", "correct_choice", "is_true", "correct_order",
                   "match_left", "match_right", "explanation", "status"]


class Invalid(Exception):
    """The folder breaks a content rule; nothing was uploaded."""


# ---------------------------------------------------------------- reading and checking


def full_id(source_id, card):
    """`tetris-quote` inside source `happiness-advantage` means `happiness-advantage/tetris-quote`."""
    return card if "/" in card else f"{source_id}/{card}"


def bucket_path(role, ext, source_id, card_id=None):
    """Where a file goes: media/sources/<id>/cover.jpg, source-files/<id>/text.txt, media/cards/<card id>/image.webp."""
    ext = ".jpg" if ext == ".jpeg" else ext
    if role in ("original", "text"):
        return "source-files", f"{source_id}/{FILES[role][1]}{ext}"
    if role == "cover":
        return "media", f"sources/{source_id}/cover{ext}"
    name = FILES[role][1] or MEDIA_NAME.get(ext, "image")
    return "media", f"cards/{card_id}/{name}{ext}"


def load_folder(path):
    """Returns the source.json files under `path`: the folder itself, or each folder inside it."""
    if os.path.isfile(os.path.join(path, "source.json")):
        folders = [path]
    else:
        folders = sorted(os.path.join(path, f) for f in os.listdir(path)
                         if os.path.isfile(os.path.join(path, f, "source.json")))
    if not folders:
        raise Invalid(f"No source.json in {path} or its folders.")
    out = []
    for folder in folders:
        with open(os.path.join(folder, "source.json"), encoding="utf-8") as f:
            try:
                out.append((folder, json.load(f)))
            except json.JSONDecodeError as e:
                raise Invalid(f"{folder}/source.json is not valid JSON: {e}")
    return out


def validate(batch, known_topics, known_cards=frozenset(), check_files=True):
    """Checks every rule before anything is uploaded. Returns the plan: rows and files per source.

    batch: [(folder, source_json)]; known_topics / known_cards: ids already in the database."""
    errors = []
    plans = []
    seen_sources, card_ids, practice_ids = set(), set(), set()

    def need(ok, msg):
        if not ok:
            errors.append(msg)
        return ok

    for folder, s in batch:
        sid = s.get("id", "")
        where = f"{sid or folder}"
        need(SLUG.match(sid or "") is not None, f"{where}: source id must be lowercase words joined by hyphens")
        need(os.path.basename(os.path.normpath(folder)) == sid, f"{where}: the folder name must equal the source id")
        need(sid not in seen_sources, f"{where}: source id used twice")
        seen_sources.add(sid)
        kind = s.get("kind")
        need(kind in KINDS, f"{where}: kind must be one of {sorted(KINDS)}")
        need(bool(s.get("title")), f"{where}: title is required")
        need(isinstance(s.get("authors", []), list), f"{where}: authors must be a list")
        need(s.get("status", "published") in STATUSES, f"{where}: status must be one of {sorted(STATUSES)}")
        for k in DETAILS:
            if k in s:
                need(k == kind, f"{where}: '{k}' details only belong to a source of kind {k}")
                table, allowed = DETAILS[k]
                extra = set(s[k]) - allowed
                need(not extra, f"{where}: unknown {k} fields {sorted(extra)}")
        if kind == "book" and s.get("book", {}).get("pages") is not None:
            need(isinstance(s["book"]["pages"], int) and s["book"]["pages"] > 0, f"{where}: pages must be more than 0")
        for t in s.get("topics", []):
            need(t in known_topics, f"{where}: unknown topic '{t}'")

        files = []

        def add_file(role, rel, card_id=None):
            if isinstance(rel, dict):
                path = rel.get("existing")
                if not need(set(rel) == {"existing"} and isinstance(path, str),
                            f"{card_id or where}: existing file must be {{'existing': '<storage path>'}}"):
                    return None
                ext = os.path.splitext(path)[1].lower()
                need(ext in FILES[role][0] and path == bucket_path(role, ext, sid, card_id)[1],
                     f"{card_id or where}: existing {role} path must belong to this item and role")
                return path
            ext = os.path.splitext(rel)[1].lower()
            label = f"{card_id or where}: {role} '{rel}'"
            if not need(ext in FILES[role][0], f"{label} must end in one of {sorted(FILES[role][0])}"):
                return None
            local = os.path.join(folder, rel)
            if check_files:
                need(os.path.isfile(local), f"{label}: file not found")
            bucket, path = bucket_path(role, ext, sid, card_id)
            files.append((local, bucket, path))
            return path

        src_row = {"id": sid, **{k: s.get(k) for k in SOURCE_FIELDS}}
        src_row["authors"] = s.get("authors", [])
        src_row["language"] = s.get("language", "en")
        src_row["status"] = s.get("status", "published")
        src_row["is_sample"] = s.get("is_sample", False) is True
        for role, col in (("cover", "cover_path"), ("original", "original_path"), ("text", "text_path")):
            src_row[col] = add_file(role, s[role]) if s.get(role) else None

        cards, card_topics, related, practice, links = [], [], [], [], []
        for i, c in enumerate(s.get("discover_cards", [])):
            name = c.get("id", "")
            cid = f"{sid}/{name}"
            here = f"{cid}"
            need(SLUG.match(name) is not None, f"{here}: card id must be lowercase words joined by hyphens, without the source id")
            need(cid not in card_ids, f"{here}: card id used twice")
            card_ids.add(cid)
            fmt = c.get("format")
            need(fmt in FORMATS, f"{here}: format must be one of {sorted(FORMATS)}")
            need(bool(c.get("title")), f"{here}: title is required")
            need(bool(c.get("front")), f"{here}: front is required")
            need(c.get("status", "published") in STATUSES, f"{here}: status must be one of {sorted(STATUSES)}")
            need(c.get("level") in LEVELS | {None}, f"{here}: level must be one of {sorted(LEVELS)}")
            need(fmt != "quote" or bool(c.get("speaker")), f"{here}: a quote needs a speaker")
            need(fmt not in ("image", "video", "audio") or bool(c.get("media")), f"{here}: a {fmt} card needs a media file")
            need(fmt != "news" or kind == "news", f"{here}: a news card must come from a news source")
            need(fmt not in ("image", "video") or bool(c.get("media_alt")), f"{here}: say what the {fmt} shows in media_alt")
            d = c.get("duration_seconds")
            need(d is None or (isinstance(d, int) and d > 0), f"{here}: duration_seconds must be more than 0")
            row = {"id": cid, "source_id": sid, **{k: c.get(k) for k in CARD_FIELDS}}
            row["position"] = c.get("position", i + 1)
            row["language"] = c.get("language", src_row["language"])
            row["status"] = c.get("status", "published")
            for role, col in (("media", "media_path"), ("poster", "poster_path"), ("captions", "captions_path")):
                row[col] = add_file(role, c[role], cid) if c.get(role) else None
            cards.append(row)
            for t in c.get("topics", []):
                need(t in known_topics, f"{here}: unknown topic '{t}'")
                card_topics.append({"discover_card_id": cid, "topic_id": t})
            for r in c.get("related", []):
                other = full_id(sid, r)
                need(other != cid, f"{here}: a card cannot be related to itself")
                pair = sorted([cid, other])
                related.append({"discover_card_id": pair[0], "related_card_id": pair[1]})

        for p in s.get("practice_cards", []):
            name = p.get("id", "")
            pid = f"{sid}/{name}"
            here = pid
            need(SLUG.match(name) is not None, f"{here}: practice id must be lowercase words joined by hyphens, without the source id")
            need(pid not in practice_ids, f"{here}: practice id used twice")
            practice_ids.add(pid)
            t = p.get("type")
            need(t in TYPES, f"{here}: type must be one of {sorted(TYPES)}")
            need(bool(p.get("prompt")), f"{here}: prompt is required")
            need(p.get("status", "published") in STATUSES, f"{here}: status must be one of {sorted(STATUSES)}")
            if t == "flashcard":
                need(bool(p.get("answer")), f"{here}: a flashcard needs an answer")
            elif t == "multiple_choice":
                ch = p.get("choices") or []
                need(2 <= len(ch) <= 6, f"{here}: multiple choice needs 2 to 6 choices")
                cc = p.get("correct_choice")
                need(isinstance(cc, int) and 0 <= cc < len(ch), f"{here}: correct_choice must point at a choice (0 = first)")
            elif t == "true_false":
                need(isinstance(p.get("is_true"), bool), f"{here}: true/false needs is_true: true or false")
            elif t == "ordering":
                need(len(p.get("correct_order") or []) >= 2, f"{here}: ordering needs at least 2 items")
            elif t == "matching":
                left, right = p.get("match_left") or [], p.get("match_right") or []
                need(len(left) >= 2 and len(left) == len(right), f"{here}: matching needs 2+ left items and as many right items")
            tests = p.get("tests") or []
            need(bool(tests), f"{here}: list the Discover cards it tests in 'tests'")
            practice.append({"id": pid, "source_id": sid, **{k: p.get(k) for k in PRACTICE_FIELDS},
                             "status": p.get("status", "published")})
            for d in tests:
                links.append({"discover_card_id": full_id(sid, d), "practice_card_id": pid})

        plans.append({"source": src_row, "kind": kind, "folder": folder,
                      "details": details_row(sid, kind, s.get(kind, {})) if kind in DETAILS else None,
                      "topics": [{"source_id": sid, "topic_id": t} for t in s.get("topics", [])],
                      "cards": cards, "card_topics": card_topics, "related": related,
                      "practice": practice, "links": links, "files": files})

    every_card = card_ids | set(known_cards)
    for plan in plans:
        for r in plan["related"]:
            for c in (r["discover_card_id"], r["related_card_id"]):
                need(c in every_card, f"{plan['source']['id']}: related card '{c}' is not a known card id")
        for link in plan["links"]:
            need(link["discover_card_id"] in every_card,
                 f"{link['practice_card_id']}: tests unknown card '{link['discover_card_id']}'")
    if errors:
        raise Invalid("\n".join(errors))
    return plans


def details_row(sid, kind, given):
    """Every detail column is sent, so a field taken out of source.json is cleared too."""
    row = {"source_id": sid, **{k: given.get(k) for k in sorted(DETAILS[kind][1])}}
    if kind == "paper":
        row["paper_status"] = given.get("paper_status", "published")
    return row


def outside_card_refs(batch):
    """Card ids pointed at by links that belong to sources outside the batch (they must already exist)."""
    inside = {s.get("id") for _, s in batch}
    refs = set()
    for _, s in batch:
        sid = s.get("id", "")
        for c in s.get("discover_cards", []):
            refs |= {full_id(sid, r) for r in c.get("related", [])}
        for p in s.get("practice_cards", []):
            refs |= {full_id(sid, d) for d in p.get("tests") or []}
    return {r for r in refs if r.split("/")[0] not in inside}


def validate_topics(topics):
    errors, ids = [], {t.get("id") for t in topics}
    mains = {t["id"] for t in topics if not t.get("parent")}
    for t in topics:
        tid = t.get("id") or ""
        if not SLUG.match(tid):
            errors.append(f"topic '{tid}': id must be lowercase words joined by hyphens")
        if not t.get("name"):
            errors.append(f"topic '{tid}': name is required")
        if t.get("parent") and t["parent"] not in mains:
            errors.append(f"topic '{tid}': parent '{t['parent']}' must be a main area in this file")
    # Sub-topics split an area into 2 or more variations; one alone means the area itself.
    for area in sorted(mains):
        subs = [t["id"] for t in topics if t.get("parent") == area]
        if len(subs) == 1:
            errors.append(f"topic '{area}': its only sub-topic is '{subs[0]}'. Remove it and use '{area}' alone")
    if len(ids) != len(topics):
        errors.append("a topic id is used twice")
    if errors:
        raise Invalid("\n".join(errors))


# ---------------------------------------------------------------- talking to Supabase


class Supabase:
    def __init__(self):
        env = {}
        with open(os.path.join(ROOT, ".env"), encoding="utf-8") as f:
            for line in f:
                if "=" in line and not line.lstrip().startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip().strip('"')
        self.url = env["SUPABASE_URL"].rstrip("/")
        key = env["SUPABASE_SERVICE_ROLE_KEY"]
        # The service-role key passes the access rules: never put it in the app.
        self.headers = {"apikey": key, "Authorization": f"Bearer {key}", "User-Agent": "smartscrolling-upload/1.0"}

    def call(self, method, path, body=None, headers=None, raw=False):
        data = body if raw or body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.url + path, data=data, method=method,
                                     headers={"Content-Type": "application/json", **self.headers, **(headers or {})})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                text = r.read()
                return json.loads(text) if text else None
        except urllib.error.HTTPError as e:
            raise SystemExit(f"{method} {path} failed ({e.code}): {e.read().decode()[:500]}")

    def select(self, table, query):
        return self.call("GET", f"/rest/v1/{table}?{query}")

    def upsert(self, table, rows, conflict):
        if rows:
            self.call("POST", f"/rest/v1/{table}?on_conflict={conflict}", rows,
                      {"Prefer": "resolution=merge-duplicates,return=minimal"})

    def delete(self, table, query):
        self.call("DELETE", f"/rest/v1/{table}?{query}", headers={"Prefer": "return=minimal"})

    def update(self, table, query, values):
        self.call("PATCH", f"/rest/v1/{table}?{query}", values, {"Prefer": "return=minimal"})

    def put_file(self, local, bucket, path):
        with open(local, "rb") as f:
            data = f.read()
        info = self.call("POST", f"/storage/v1/object/list/{bucket}",
                         {"prefix": os.path.dirname(path), "search": os.path.basename(path)})
        etag = next((o.get("metadata", {}).get("eTag") for o in info or [] if o["name"] == os.path.basename(path)), None)
        if etag and etag.strip('"') == hashlib.md5(data).hexdigest():
            return False
        ctype = mimetypes.guess_type(local)[0] or "application/octet-stream"
        if ctype.startswith("text/"):
            ctype += "; charset=utf-8"
        self.call("POST", f"/storage/v1/object/{bucket}/{urllib.parse.quote(path)}", data,
                  {"Content-Type": ctype, "x-upsert": "true"}, raw=True)
        return True

    def list_files(self, bucket, prefix):
        out = []
        for o in self.call("POST", f"/storage/v1/object/list/{bucket}", {"prefix": prefix, "limit": 1000}) or []:
            path = f"{prefix}/{o['name']}"
            out += self.list_files(bucket, path) if o.get("id") is None else [path]
        return out


def ids_in(values):
    return "in.(" + ",".join(urllib.parse.quote(f'"{v}"') for v in values) + ")"


def changed(new_rows, old_rows):
    """Rows that are new, and rows whose sent fields differ from the database."""
    old = {r["id"]: r for r in old_rows}
    fresh = [r for r in new_rows if r["id"] not in old]
    updated = [r for r in new_rows if r["id"] in old and any(old[r["id"]].get(k) != v for k, v in r.items())]
    return fresh, updated


# ---------------------------------------------------------------- commands


def upload(path, dry_run):
    db = Supabase()
    batch = load_folder(path)
    topics = {t["id"] for t in db.select("topics", "select=id")}
    outside = outside_card_refs(batch)
    known = {c["id"] for c in db.select("discover_cards", f"select=id&id={ids_in(outside)}")} if outside else set()
    plans = validate(batch, topics, known)
    sids = [p["source"]["id"] for p in plans]
    old_sources = db.select("sources", f"select=*&id={ids_in(sids)}")
    old_cards = db.select("discover_cards", f"select=*&source_id={ids_in(sids)}")
    old_practice = db.select("practice_cards", f"select=*&source_id={ids_in(sids)}")
    # A reference may retain an attached file, never attach another item's file.
    existing = {r["id"]: r for r in old_sources + old_cards}
    for _, source in batch:
        items = [(source["id"], source, ("cover", "original", "text"))]
        items += [(full_id(source["id"], c["id"]), c, ("media", "poster", "captions"))
                  for c in source.get("discover_cards", [])]
        for item_id, item, roles in items:
            for role in roles:
                if isinstance(item.get(role), dict) and existing.get(item_id, {}).get(role + "_path") != item[role]["existing"]:
                    raise Invalid(f"{item_id}: existing {role} is not the currently attached file")
    sources = [p["source"] for p in plans]
    cards = [c for p in plans for c in p["cards"]]
    practice = [c for p in plans for c in p["practice"]]
    new_s, upd_s = changed(sources, old_sources)
    new_c, upd_c = changed(cards, old_cards)
    new_p, upd_p = changed(practice, old_practice)
    keep_c, keep_p = {c["id"] for c in cards}, {c["id"] for c in practice}
    hide_c = [c["id"] for c in old_cards if c["id"] not in keep_c and c["status"] != "hidden"]
    hide_p = [c["id"] for c in old_practice if c["id"] not in keep_p and c["status"] != "hidden"]
    summary = (f"{len(new_s)} new sources, {len(upd_s)} updated; "
               f"{len(new_c)} new cards, {len(upd_c)} updated, {len(hide_c)} hidden; "
               f"{len(new_p)} new tests, {len(upd_p)} updated, {len(hide_p)} hidden")
    if dry_run:
        print("Dry run, nothing uploaded. Would make:", summary)
        return
    sent = sum(db.put_file(*f) for p in plans for f in p["files"])
    db.upsert("sources", new_s + upd_s, "id")
    for p in plans:
        sid = p["source"]["id"]
        if p["details"]:
            db.upsert(DETAILS[p["kind"]][0], [p["details"]], "source_id")
        db.upsert("source_topics", p["topics"], "source_id,topic_id")
        keep = [t["topic_id"] for t in p["topics"]]
        db.delete("source_topics", f"source_id=eq.{sid}" + (f"&topic_id=not.{ids_in(keep)}" if keep else ""))
    db.upsert("discover_cards", new_c + upd_c, "id")
    db.upsert("practice_cards", new_p + upd_p, "id")
    for p in plans:
        sync_links(db, "card_topics", p["card_topics"], [c["id"] for c in p["cards"]], ("discover_card_id", "topic_id"))
        sync_links(db, "practice_links", p["links"], [c["id"] for c in p["practice"]], ("practice_card_id", "discover_card_id"))
        # Pairs inside this source follow the folder; links to cards of other sources are only added.
        sync_links(db, "related_cards", p["related"], [], ("discover_card_id", "related_card_id"))
        want = {(r["discover_card_id"], r["related_card_id"]) for r in p["related"]}
        sid = p["source"]["id"]
        for r in db.select("related_cards", f"select=*&discover_card_id=like.{sid}/*&related_card_id=like.{sid}/*"):
            if (r["discover_card_id"], r["related_card_id"]) not in want:
                db.delete("related_cards", f"discover_card_id=eq.{urllib.parse.quote(r['discover_card_id'])}"
                                           f"&related_card_id=eq.{urllib.parse.quote(r['related_card_id'])}")
    if hide_c:
        db.update("discover_cards", f"id={ids_in(hide_c)}", {"status": "hidden"})
    if hide_p:
        db.update("practice_cards", f"id={ids_in(hide_p)}", {"status": "hidden"})
    print(f"Uploaded {sent} changed files. {summary}")


def sync_links(db, table, rows, owners, cols):
    """Makes the link rows owned by `owners` (in column cols[0]) exactly `rows`."""
    unique = [dict(t) for t in {tuple(sorted(r.items())) for r in rows}]
    db.upsert(table, unique, ",".join(sorted(cols)))
    if not owners:
        return
    want = {(r[cols[0]], r[cols[1]]) for r in unique}
    for r in db.select(table, f"select={cols[0]},{cols[1]}&{cols[0]}={ids_in(owners)}"):
        if (r[cols[0]], r[cols[1]]) not in want:
            db.delete(table, f"{cols[0]}=eq.{urllib.parse.quote(r[cols[0]])}&{cols[1]}=eq.{urllib.parse.quote(r[cols[1]])}")


def upload_topics():
    with open(os.path.join(HERE, "topics.json"), encoding="utf-8") as f:
        topics = json.load(f)
    validate_topics(topics)
    rows = [{"id": t["id"], "name": t["name"], "parent_id": t.get("parent"), "position": t.get("position", i)}
            for i, t in enumerate(topics)]
    db = Supabase()
    old = db.select("topics", "select=*")
    new, upd = changed(rows, old)
    # Main areas first, so a sub-topic's parent always exists.
    db.upsert("topics", [r for r in new + upd if not r["parent_id"]], "id")
    db.upsert("topics", [r for r in new + upd if r["parent_id"]], "id")
    extra = {t["id"] for t in old} - {r["id"] for r in rows}
    # A sub-topic removed from the file: people's follow or hide moves to its
    # main area, then it goes. It fails while a source or card still uses it.
    gone = sorted(t["id"] for t in old if t["id"] in extra and t["parent_id"])
    for t in (t for t in old if t["id"] in gone):
        choices = db.select("user_topics", f"topic_id=eq.{t['id']}&select=user_id,choice")
        if choices:
            db.call("POST", "/rest/v1/user_topics?on_conflict=user_id,topic_id",
                    [{**c, "topic_id": t["parent_id"]} for c in choices],
                    {"Prefer": "resolution=ignore-duplicates,return=minimal"})
        db.delete("topics", f"id=eq.{t['id']}")
    extra -= set(gone)
    print(f"{len(new)} new topics, {len(upd)} updated" + (f", {len(gone)} sub-topics removed: {gone}" if gone else "")
          + (f"; kept {len(extra)} not in topics.json: {sorted(extra)}" if extra else ""))


def purge_samples(dry_run):
    db = Supabase()
    samples = db.select("sources", "select=id,title&is_sample=eq.true&order=id")
    for s in samples:
        print(f"  {s['id']}: {s['title']}")
    if dry_run or not samples:
        print(f"{'Dry run: would delete' if dry_run else 'Deleted'} {len(samples) if dry_run else 0} sample sources.")
        return
    ids = [s["id"] for s in samples]
    for sid in ids:
        for bucket, prefix in (("media", f"sources/{sid}"), ("media", f"cards/{sid}"), ("source-files", sid)):
            files = db.list_files(bucket, prefix)
            if files:
                db.call("DELETE", f"/storage/v1/object/{bucket}", {"prefixes": files})
    # Only is_sample rows: real content is never deleted (D41). Everything under them goes by cascade.
    db.delete("sources", f"is_sample=eq.true&id={ids_in(ids)}")
    print(f"Deleted {len(ids)} sample sources with their cards, tests and files.")


def requests(done):
    db = Supabase()
    if done:
        db.update("content_requests", f"id=eq.{done}&status=eq.open", {"status": "done", "resolved_at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
        print(f"Marked {done} done.")
        return
    rows = db.select("content_requests", "select=*&status=eq.open&order=created_at")
    for r in rows:
        about = r["discover_card_id"] or r["practice_card_id"] or r["source_id"] or "-"
        print(f"{r['id']}  {r['created_at'][:10]}  {r['kind']:<13} {about}  {r['message'] or ''}")
    print(f"{len(rows)} open to-dos.")


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    dry = "--dry-run" in argv
    try:
        if not args:
            print(__doc__)
        elif args[0] == "topics":
            upload_topics()
        elif args[0] == "purge-samples":
            purge_samples(dry)
        elif args[0] == "requests":
            requests(args[1] if "--done" in argv and len(args) > 1 else None)
        else:
            upload(args[0], dry)
    except Invalid as e:
        print("Nothing uploaded. Fix these first:\n" + str(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
