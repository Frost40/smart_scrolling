"""The intake allowlist and the attribution saved at the end of each description."""
import re

from tools.content import upload

NEWSDATA = 'NewsData.io personal/internal use'
CURRENTS = 'Currents authorized use'


def normalize(value):
    value = (value or '').strip()
    if value in (NEWSDATA, CURRENTS):
        return value
    name = value.lower().strip().rstrip('/')
    name = re.sub(r'^https?://(?:www\.)?creativecommons.org/', '', name)
    name = re.sub(r'^(?:licenses/|publicdomain/)', '', name)
    name = name.replace('zero/', 'cc0 ').replace('mark/', 'public domain ')
    name = re.sub(r'[-_/\s]+', ' ', name).strip()
    if re.fullmatch(r'(public domain|pd)(?: 1\.0)?', name):
        return 'Public domain'
    if re.fullmatch(r'cc0(?: 1\.0)?', name):
        return 'CC0'
    match = re.fullmatch(r'(?:cc )?(by(?: nc)?(?: sa| nd)?)(?: (\d\.\d))?', name)
    if not match:
        return 'unknown'
    return 'CC ' + match[1].upper().replace(' ', '-') + (f' {match[2]}' if match[2] else '')


def allowed(value, allow_noncommercial=True):
    license = normalize(value)
    return license != 'unknown' and '-ND' not in license and (
        allow_noncommercial or ('-NC' not in license and license not in (NEWSDATA, CURRENTS)))


def attribution(meta):
    license = normalize(meta.get('license'))
    credit = (meta.get('credit') or '').strip().rstrip('.')
    if license == 'unknown':
        return ''
    if license == NEWSDATA:
        publisher = (meta.get('details') or {}).get('newspaper') or credit
        return (f'Facts from {publisher}. License: {license}. '
                'Powered by NewsData.io API (https://newsdata.io/). News data by NewsData.io.')
    return f'Adapted from {credit or meta["link"]}, {license}.'


def source_license(description):
    """Read only our trailing credit, not incidental license words in the summary."""
    description = description or ''
    if description.endswith('News data by NewsData.io.') and f'License: {NEWSDATA}.' in description:
        return NEWSDATA
    match = re.search(r'Adapted from .+, ([^,\n]+)\.$', description)
    return normalize(match[1]) if match else 'unknown'


def inventory():
    client, offset = upload.Supabase(), 0
    while rows := client.select('sources', f'select=id,kind,description&order=id&limit=1000&offset={offset}'):
        for row in rows:
            license = source_license(row.get('description'))
            yield {'id': row['id'], 'kind': row['kind'], 'license': license,
                   'noncommercial': '-NC' in license or license in (NEWSDATA, CURRENTS)}
        offset += len(rows)
