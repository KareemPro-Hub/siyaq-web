#!/usr/bin/env python3
"""Import ONLY provider-verified Quranpedia dumps; preserve canonical verse text."""
import argparse
import datetime
import gzip
import hashlib
import json
import re
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'data/source'
HEADERS = {'User-Agent': 'Siyaq/0.1 (Quran quotation research; quranpedia.net attribution)', 'Cache-Control': 'no-cache'}
FILES = ['mushafs-1.json.gz', 'tafsir-book-269.json.gz', 'tafsir-book-27758.json.gz']

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')

class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_data(self, text):
        self.parts.append(text)
    def handle_starttag(self, tag, attrs):
        if tag in ['br', 'p', 'div']:
            self.parts.append('\n')
    def handle_endtag(self, tag):
        if tag in ['p', 'div']:
            self.parts.append('\n')

def plain(text):
    parser = PlainText()
    parser.feed(text)
    return re.sub(r'[ \t\u00a0]+', ' ', ''.join(parser.parts)).strip()

def transform_tafsir(books):
    result = {}
    for book in books:
        for ayah in book['ayahs']:
            key = f"{ayah['surah']}:{ayah['ayah']}"
            for c in ayah['content']:
                if c.get('text'):
                    result.setdefault(key, []).append({'bookId': book['book']['id'], 'bookName': book['book']['name'], 'author': book['book']['author']['ar_name'], 'part': str(c.get('part') or ''), 'page': c.get('page'), 'text': plain(c['text']), 'url': f"https://quranpedia.net/api/v1/ayah/{ayah['surah']}/{ayah['ayah']}/book/{book['book']['id']}"})
    return result

def verify():
    p = json.loads((ROOT / 'data/provenance.json').read_text())
    for name, expected in p['processed_sha256'].items():
        assert digest((ROOT / 'data' / name).read_bytes()) == expected, 'Processed data changed: ' + name
    q = json.loads((ROOT / 'data/quran.json').read_text())
    assert len(q) == 6236
    assert len({(v['surah'], v['ayah']) for v in q}) == 6236
    assert len({v['surah'] for v in q}) == 114
    tafsir = json.loads((ROOT / 'data/tafsir.json').read_text())
    assert set(tafsir).issubset({v['id'] for v in q}), 'Invalid tafsir position'
    policy = json.loads((ROOT / 'data/source-policy.json').read_text())
    assert {row['bookId'] for rows in tafsir.values() for row in rows}.issubset({b['bookId'] for b in policy['tafsir_books']})
    if all((SOURCE / n).exists() for n in FILES):
        manifest = json.loads((SOURCE / 'manifest.json').read_text())
        for name in FILES:
            expected = next(r['sha256'] for r in manifest['files'] if r['name'] == name)
            assert digest((SOURCE / name).read_bytes()) == expected, name
        original = json.loads(gzip.decompress((SOURCE / FILES[0]).read_bytes()))['data']
        canonical = {(s['id'], a['number']): a['text'] for s in original['surahs'] for a in s['ayahs']}
        assert all(v['text'] == canonical[(v['surah'], v['ayah'])] for v in q), 'Canonical text was modified'
        books = [json.loads(gzip.decompress((SOURCE / name).read_bytes())) for name in FILES[1:]]
        assert tafsir == transform_tafsir(books), 'Tafsir or attribution changed'
    print('Verified: 6236 unique verses / 114 surahs; tafsir positions, policy and hashes match.')

def run():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    records = []
    datasets = []
    for name in FILES:
        path = SOURCE / name
        rec = next(r for r in manifest['files'] if r['name'] == name)
        if not path.exists():
            request = urllib.request.Request('https://api.quranpedia.net/dumps/' + name, headers=HEADERS)
            raw = urllib.request.urlopen(request, timeout=60).read()
            assert digest(raw) == rec['sha256'], 'Provider checksum mismatch: ' + name
            path.write_bytes(raw)
        raw = path.read_bytes()
        assert digest(raw) == rec['sha256'], 'Provider checksum mismatch: ' + name
        data = json.loads(gzip.decompress(raw))
        datasets.append(data)
        records.append({**rec, 'url': 'https://api.quranpedia.net/dumps/' + name, 'license_version': data['license']['version']})
    verses = [{'id': f"{s['id']}:{a['number']}", 'surah': s['id'], 'surahName': s['name'].removeprefix('سورة ').strip(), 'ayah': a['number'], 'text': a['text']} for s in datasets[0]['data']['surahs'] for a in s['ayahs']]
    assert len(verses) == 6236
    tafsir = transform_tafsir(datasets[1:])
    save_json(ROOT / 'data/quran.json', verses)
    save_json(ROOT / 'data/tafsir.json', tafsir)
    save_json(ROOT / 'data/provenance.json', {'provider': 'Quranpedia.net — الموسوعة القرآنية', 'source': 'https://quranpedia.net', 'version': manifest['version'], 'imported_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'files': records, 'verses': len(verses), 'surahs': 114, 'tafsir_ayahs': len(tafsir), 'books': [{'id': b['book']['id'], 'name': b['book']['name'], 'ayahs': len(b['ayahs']), 'author': b['book']['author']['ar_name']} for b in datasets[1:]], 'license_url': 'https://api.quranpedia.net/dumps/LICENSE.md', 'processed_sha256': {n: digest((ROOT / 'data' / n).read_bytes()) for n in ['quran.json', 'tafsir.json']}})
    verify()
    print('Available tafsir:', len(tafsir), 'verse positions; no full-coverage claim.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    verify() if args.verify else run()
