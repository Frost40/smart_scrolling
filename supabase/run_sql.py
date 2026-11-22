"""Runs a SQL file on the live Supabase project through the Management API.

    python supabase/run_sql.py supabase/tests/access_rules.sql
    python supabase/run_sql.py --migration supabase/migrations/<timestamp>_<what>.sql

--migration also records the file in the migration history, so the history matches supabase/migrations/.
Uses SUPABASE_URL and SUPABASE_ACCESS_TOKEN from the root .env. Standard library only.
"""

import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def env():
    values = {}
    with open(os.path.join(ROOT, ".env"), encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"')
    return values


def run(query):
    e = env()
    ref = e["SUPABASE_URL"].split("//")[1].split(".")[0]
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={
            "Authorization": f"Bearer {e['SUPABASE_ACCESS_TOKEN']}",
            "Content-Type": "application/json",
            # The API rejects Python's default user agent.
            "User-Agent": "smartscrolling-tools/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read() or b"null")


def main(args):
    migration = "--migration" in args
    path = [a for a in args if a != "--migration"][0]
    with open(path, encoding="utf-8") as f:
        query = f.read()
    if migration:
        version, name = os.path.basename(path)[:-4].split("_", 1)
        statements = json.dumps([query]).replace("'", "''")
        query = (
            f"begin;\n{query}\n;insert into supabase_migrations.schema_migrations (version, name, statements) "
            f"select '{version}', '{name}', array(select jsonb_array_elements_text('{statements}'::jsonb));\ncommit;"
        )
    try:
        print(json.dumps(run(query), indent=1, default=str))
    except urllib.error.HTTPError as err:
        print(err.read().decode(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
