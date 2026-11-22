"""From a book file to numbered paragraphs and chunks (design section 10.3).

A converter returns blocks: [{"text": ..., "heading": bool}]. Headings are marked
while converting (EPUB <h1>-<h3>, or the plain-text rule) and never guessed later.
"""

from html.parser import HTMLParser
import json
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

from . import settings

# The 50 most common English words (design 10.3, language check).
COMMON = set("""the be to of and a in that have i it for not on with he as you do at this but his by from
they we say her she or an will my one all would there their what so up out if about who get which go me""".split())
BACK_PARTS = {"notes", "references", "bibliography", "index", "acknowledgements", "acknowledgments", "about the author"}
# A chapter label: a word such as Chapter, a number, or a real Roman numeral ("Civil" is not one).
CHAPTER = re.compile(r"^((chapter|part|book|lecture|section)\b|\d+\b|(?=[ivxlc])c{0,3}(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})([.:)]|\s|$))", re.I)


def is_heading_line(text):
    """Plain-text heading rule: at most 12 words, no full stop at the end, and
    starting with Chapter, Part or a number, or written all in capitals."""
    words = text.split()
    if not words or len(words) > 12 or text.rstrip().endswith("."):
        return False
    letters = [c for c in text if c.isalpha()]
    return bool(re.match(r"(chapter|part)\b|\d", text, re.I)) or (bool(letters) and all(c.isupper() for c in letters))


def _clean(text):
    return re.sub(r"\s+", " ", text).strip()


def text_to_blocks(text):
    return [{"text": t, "heading": is_heading_line(t)}
            for t in (_clean(part) for part in re.split(r"\n\s*\n", text)) if t]


# ---------------------------------------------------------------- EPUB

class _Html(HTMLParser):
    BLOCKS = {"p", "div", "li", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "tr",
              "section", "table", "ul", "ol", "dd", "dt", "figcaption", "body"}
    SKIP = {"script", "style", "head", "title", "sup"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks, self.buffer, self.skip, self.heading = [], [], 0, 0
        self.anchor = None  # (is a note link, buffered text) while inside <a>

    def flush(self):
        text = _clean("".join(self.buffer))
        if text:
            self.blocks.append({"text": text, "heading": self.heading > 0})
        self.buffer = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in self.SKIP:
            self.skip += 1
        elif tag in self.BLOCKS:
            self.flush()
            if tag in ("h1", "h2", "h3"):
                self.heading += 1
        elif tag == "br":
            self.buffer.append(" ")
        elif tag == "a":
            kind = (attrs.get("epub:type") or "") + " " + (attrs.get("role") or "")
            self.anchor = ["noteref" in kind, []]

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCKS:
            self.flush()
            if tag in ("h1", "h2", "h3"):
                self.heading = max(0, self.heading - 1)
        elif tag == "a" and self.anchor is not None:
            note, parts = self.anchor
            self.anchor = None
            text = "".join(parts)
            # Footnote links: marked as such, or just a number, a star or [n].
            if not note and not re.fullmatch(r"\s*[\[(]?(\d+|\*+|[a-z])[\])]?\s*", text):
                self.buffer.append(text)

    def handle_data(self, data):
        if self.skip:
            return
        (self.anchor[1] if self.anchor is not None else self.buffer).append(data)


def _local(tag):
    return tag.rsplit("}", 1)[-1]


def _opf(book):
    container = ET.fromstring(book.read("META-INF/container.xml"))
    path = next(e.get("full-path") for e in container.iter() if _local(e.tag) == "rootfile")
    return path, ET.fromstring(book.read(path))


def epub_facts(path):
    """Title, authors and language from the EPUB's own metadata."""
    with zipfile.ZipFile(path) as book:
        _, opf = _opf(book)
    facts = {"title": "", "authors": [], "language": ""}
    for e in opf.iter():
        name, text = _local(e.tag), (e.text or "").strip()
        if name == "title" and text and not facts["title"]:
            facts["title"] = text
        elif name == "creator" and text:
            facts["authors"].append(text)
        elif name == "language" and text and not facts["language"]:
            facts["language"] = text
    return facts


def epub_to_text(path):
    """Blocks in the reading order of the .opf spine."""
    with zipfile.ZipFile(path) as book:
        opf_path, opf = _opf(book)
        base = posixpath.dirname(opf_path)
        items = {e.get("id"): e.get("href") for e in opf.iter() if _local(e.tag) == "item"}
        blocks = []
        for ref in (e for e in opf.iter() if _local(e.tag) == "itemref"):
            href = items.get(ref.get("idref"))
            if not href:
                continue
            name = posixpath.normpath(posixpath.join(base, urllib.parse.unquote(href)))
            parser = _Html()
            parser.feed(book.read(name).decode("utf-8", "replace"))
            parser.flush()
            blocks += parser.blocks
    return blocks


def epub_cover(path):
    """(bytes, extension) of the cover picture inside the EPUB, or None."""
    with zipfile.ZipFile(path) as book:
        opf_path, opf = _opf(book)
        items = [e for e in opf.iter() if _local(e.tag) == "item"]
        cover_id = next((e.get("content") for e in opf.iter()
                         if _local(e.tag) == "meta" and e.get("name") == "cover"), None)
        for item in items:
            if "cover-image" in (item.get("properties") or "") or item.get("id") == cover_id:
                ext = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}.get(item.get("media-type"))
                if ext:
                    name = posixpath.normpath(posixpath.join(posixpath.dirname(opf_path),
                                                             urllib.parse.unquote(item.get("href"))))
                    return book.read(name), ext
    return None


# ---------------------------------------------------------------- PDF

def pdf_pages_to_blocks(raw):
    """Turn `pdftotext -layout` output (pages split by form feeds) into blocks."""
    pages = [page.splitlines() for page in raw.split("\f")]
    pages = [page for page in pages if any(line.strip() for line in page)]
    words = sum(len(line.split()) for page in pages for line in page)
    if not pages or words / len(pages) < 100:
        raise ValueError("scanned PDF")

    def key(line):
        return re.sub(r"\d+", "#", _clean(line).lower())
    # Headers, footers and page numbers: lines that repeat on most pages.
    counts = {}
    for page in pages:
        for k in {key(line) for line in page if line.strip()}:
            counts[k] = counts.get(k, 0) + 1
    repeated = {k for k, n in counts.items() if len(pages) > 1 and n > len(pages) / 2}

    paragraphs, current = [], []
    for page in pages:
        lines = [line for line in page if key(line) not in repeated]
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()
        if current and lines and re.search(r"[.!?:\"”’]$", current[-1]):
            paragraphs.append(current)
            current = []
        for line in lines:
            if line.strip():
                current.append(line.strip())
            elif current:
                paragraphs.append(current)
                current = []
    if current:
        paragraphs.append(current)

    blocks = []
    for lines in paragraphs:
        text = lines[0]
        for line in lines[1:]:
            if re.search(r"[A-Za-z]-$", text) and line[:1].islower():
                text = text[:-1] + line
            else:
                text += " " + line
        text = _clean(text)
        blocks.append({"text": text, "heading": is_heading_line(text)})
    return blocks


def pdf_to_text(path):
    out = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", str(path), "-"], capture_output=True,
                         encoding="utf-8", errors="replace", timeout=300, check=True).stdout
    return pdf_pages_to_blocks(out)


# ---------------------------------------------------------------- any file

def file_to_blocks(path):
    path = Path(path)
    ext = path.suffix.lower()
    if ext == ".epub":
        return epub_to_text(path)
    if ext == ".pdf":
        return pdf_to_text(path)
    if ext == ".txt":
        return text_to_blocks(path.read_text(encoding="utf-8", errors="replace"))
    if not shutil.which("ebook-convert"):
        raise ValueError("install Calibre")
    with tempfile.TemporaryDirectory() as folder:
        out = Path(folder) / "book.epub"
        subprocess.run(["ebook-convert", str(path), str(out)], capture_output=True, timeout=600, check=True)
        return epub_to_text(out)


def _words(blocks):
    return sum(len(b["text"].split()) for b in blocks)


def trim(blocks):
    """Drop the Gutenberg wrapper, short front matter and known back parts."""
    starts = [i for i, b in enumerate(blocks) if re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG", b["text"], re.I)]
    if starts:
        blocks = blocks[starts[0] + 1:]
    ends = [i for i, b in enumerate(blocks) if re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG", b["text"], re.I)]
    if ends:
        blocks = blocks[:ends[0]]
    headings = [i for i, b in enumerate(blocks) if b["heading"]]
    first = next((i for i in headings if CHAPTER.match(blocks[i]["text"])), headings[0] if headings else 0)
    if _words(blocks[:first]) < 1500:
        blocks = blocks[first:]
    total, seen = _words(blocks), 0
    for i, b in enumerate(blocks):
        if b["heading"] and seen >= 0.8 * total and b["text"].strip(" .:").lower() in BACK_PARTS:
            return blocks[:i]
        seen += len(b["text"].split())
    return blocks


def is_english(text):
    words = re.findall(r"[a-z']+", text.lower())
    return bool(words) and sum(w in COMMON for w in words) / len(words) >= 0.15


def paragraphs(blocks):
    """[{"n": 1, "text": ..., "heading": "<the heading right above it>"}]; headings are not numbered."""
    out, pending = [], []
    for b in blocks:
        if b["heading"]:
            # "I" + "THE DAILY MIRACLE" read as one heading; a title page's stack keeps only its last line.
            label = pending and len(pending[-1].split()) <= 3 and CHAPTER.match(pending[-1])
            pending = pending + [b["text"]] if label else [b["text"]]
            continue
        para = {"n": len(out) + 1, "text": b["text"]}
        if pending:
            para["heading"] = ": ".join(pending)
            pending = []
        out.append(para)
    return out


def chunks(paras, words_min, words_max):
    """Whole paragraphs only; cut at a heading once the chunk has words_min, never past words_max."""
    out, current, heading = [], None, ""
    for p in paras:
        words = len(p["text"].split())
        heading = p.get("heading", heading)
        if current and ((p.get("heading") and current["words"] >= words_min) or current["words"] + words > words_max):
            out.append(current)
            current = None
        if current is None:
            current = {"n": len(out) + 1, "heading": heading, "first": p["n"], "last": p["n"], "words": 0}
        current["last"] = p["n"]
        current["words"] += words
    if current:
        out.append(current)
    if len(out) > 1 and out[-1]["words"] < words_min and out[-2]["words"] + out[-1]["words"] <= words_max:
        last = out.pop()
        out[-1].update(last=last["last"], words=out[-1]["words"] + last["words"])
    return out


# ---------------------------------------------------------------- book facts

def _agent():
    contact = settings.secrets().get("CONTACT_EMAIL", "")
    return "SmartScrollingPipeline/1.0" + (f" ({contact})" if contact else "")


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": _agent()})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read(20_000_000)


def _norm_title(text):
    return re.sub(r"[^a-z0-9 ]", "", (text or "").split(":")[0].lower()).strip()


def book_facts(meta, folder):
    """Fill empty facts from Open Library (one request) and fetch a cover (one request).
    A failed request leaves the field empty; it never fails the job."""
    isbn = (meta.get("details") or {}).get("isbn", "")
    try:
        if isbn:
            query = {"isbn": isbn}
        else:
            query = {"title": meta.get("title", "")}
            if meta.get("authors"):
                query["author"] = meta["authors"][0]
        query.update(fields="title,first_publish_year,publisher,number_of_pages_median,cover_i", limit=1)
        docs = json.loads(_get("https://openlibrary.org/search.json?" + urllib.parse.urlencode(query))).get("docs", [])
        doc = docs[0] if docs and (isbn or _norm_title(docs[0].get("title")) == _norm_title(meta.get("title"))) else {}
    except (OSError, ValueError):
        doc = {}
    if doc.get("first_publish_year") and not meta.get("year"):
        meta["year"] = doc["first_publish_year"]
    if isbn:
        # Publisher and pages belong to one edition, so they are taken only for an ISBN match.
        details = meta.setdefault("details", {})
        if doc.get("publisher") and not details.get("publisher"):
            details["publisher"] = doc["publisher"][0]
        if doc.get("number_of_pages_median") and not details.get("pages"):
            details["pages"] = doc["number_of_pages_median"]
    cover = None
    if isbn or doc.get("cover_i"):
        url = (f"https://covers.openlibrary.org/b/isbn/{isbn}-L.jpg?default=false" if isbn
               else f"https://covers.openlibrary.org/b/id/{doc['cover_i']}-L.jpg?default=false")
        try:
            data = _get(url)
            if len(data) > 1000 and data[:3] == b"\xff\xd8\xff":
                cover = (data, ".jpg")
        except OSError:
            pass
    original = next(Path(folder).glob("original.epub"), None)
    if cover is None and original:
        try:
            cover = epub_cover(original)
        except (OSError, KeyError, zipfile.BadZipFile, ET.ParseError, StopIteration):
            cover = None
    if cover:
        (Path(folder) / ("cover" + cover[1])).write_bytes(cover[0])
        meta["cover"] = "cover" + cover[1]
    return meta
