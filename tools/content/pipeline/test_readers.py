"""Offline reader contracts; public API excerpts are saved beside these tests."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import readers

DATA = Path(__file__).with_name('testdata') / 'readers'


class ReaderTests(unittest.TestCase):
    def test_wikipedia_article_saved_response(self):
        with patch.object(readers, 'get', return_value=(DATA / 'wiki.json').read_bytes()):
            item = readers.wikipedia_article({'title': 'Physics'})[0]
        self.assertEqual(item['key'], 'wikipedia:Physics')
        self.assertTrue(item['text'])

    def test_wikipedia_current_events_adds_lead(self):
        with patch.object(readers, 'get', side_effect=[(DATA / 'current_events.json').read_bytes(),
                                                       (DATA / 'wiki.json').read_bytes()]):
            item = readers.wikipedia_current_events({'limit': 1})[0]
        self.assertIn('\n\n', item['text'])
        self.assertEqual(item['details']['newspaper'], 'Wikipedia Current events')

    def test_current_events_keeps_top_level_group_and_first_link(self):
        parser = readers._NewsList()
        parser.feed('<ul><li><a href="/wiki/Physics">Physics</a><ul><li>First report.</li>'
                    '<li>Second report.</li></ul></li><li><a href="/wiki/Biology">Biology</a></li></ul>')
        self.assertEqual(len(parser.items), 2)
        self.assertEqual(parser.items[0][1], 'Physics')
        self.assertIn('First report.', parser.items[0][0])
        self.assertIn('Second report.', parser.items[0][0])

    def test_wikipedia_daily_news(self):
        with patch.object(readers, 'get', side_effect=[(DATA / 'in_news.json').read_bytes(),
                                                       (DATA / 'wiki.json').read_bytes()]):
            item = readers.wikipedia_in_the_news({'limit': 1})[0]
        self.assertTrue(item['link'])
        self.assertTrue(item['text'])

    def test_wikipedia_vital_skips_seen_titles(self):
        from . import store
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, PIPELINE_HOME=folder):
            raw = json.loads((DATA / 'vital.json').read_bytes())
            titles = [r['title'] for r in raw['parse']['links']]
            db = store.connect()
            db.execute('INSERT INTO seen(key) VALUES (?)', ('wikipedia:' + titles[0].replace(' ', '_'),))
            db.commit()
            db.close()
            with patch.object(readers, '_api', return_value=raw), \
                    patch.object(readers, '_wiki_article', return_value={'title': titles[1], 'extract': 'Text'}) as article:
                readers.wikipedia_article({'from': 'vital'})
            self.assertEqual(article.call_args.args[0], titles[1])

    def test_nasa_saved_full_release(self):
        with patch.object(readers, 'get', return_value=(DATA / 'nasa.xml').read_bytes()):
            item = readers.nasa_news({'limit': 1})[0]
        self.assertTrue(item['text'])
        self.assertEqual(item['license'], 'Public domain')

    def test_commons_saved_license_and_credit(self):
        with patch.object(readers, 'get', return_value=(DATA / 'commons.json').read_bytes()), \
                patch.object(readers, '_seen_keys', return_value=set()), \
                patch.object(readers, '_image', return_value={'file': 'test.jpg', 'alt_source': 'Sunflower'}):
            item = readers.commons({})[0]
        self.assertTrue(item['credit'])
        self.assertTrue(item['media']['alt_source'])

    def test_met_skips_seen_before_fetch_or_image_download(self):
        with patch.object(readers, '_seen_keys', return_value={'met:1'}), \
                patch.object(readers, '_api', return_value={'objectIDs': [1, 436524]}), \
                patch.object(readers, '_json', return_value=json.loads((DATA / 'met.json').read_bytes())) as get, \
                patch.object(readers, '_image', return_value={'file': 'work.jpg', 'alt_source': 'Painting'}) as image:
            item = readers.met({})[0]
        self.assertEqual(item['key'], 'met:436524')
        self.assertEqual(get.call_count, 1)
        self.assertEqual(image.call_count, 1)

    def test_commons_skips_seen_before_image_download(self):
        raw = json.loads((DATA / 'commons.json').read_bytes())
        import copy
        row = next(iter(raw['query']['pages'].values()))
        first = copy.deepcopy(row)
        first['title'] = 'File:Already seen.jpg'
        raw['query']['pages'] = {'1': first, '2': row}
        with patch.object(readers, '_seen_keys', return_value={'commons:File:Already seen.jpg'}), \
                patch.object(readers, 'get', return_value=json.dumps(raw).encode()), \
                patch.object(readers, '_image', return_value={'file': 'image.jpg', 'alt_source': 'Painting'}) as image:
            item = readers.commons({})[0]
        self.assertEqual(item['key'], 'commons:' + row['title'])
        self.assertEqual(image.call_count, 1)

    def test_gutenberg_subject_skips_seen_before_download(self):
        catalogue = (DATA / 'gutenberg.csv').read_text(encoding='utf-8')
        catalogue += next(line for line in catalogue.splitlines() if line.startswith('14474,')).replace('14474', '99999', 1) + '\n'
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, PIPELINE_HOME=folder), \
                patch.object(readers, '_seen_keys', return_value={'gutenberg:14474'}), \
                patch.object(readers, '_download', side_effect=[catalogue.encode(), (DATA / 'gutenberg.epub').read_bytes()]) as download:
            item = readers.gutenberg({})[0]
        self.assertEqual(item['key'], 'gutenberg:99999')
        self.assertNotIn('/14474/', download.call_args.args[0])

    def test_commons_advances_past_seen_search_page(self):
        raw = json.loads((DATA / 'commons.json').read_bytes())
        row = next(iter(raw['query']['pages'].values()))
        first = {'query': {'pages': {'1': {'title': 'File:Already seen'}}},
                 'continue': {'gsroffset': 10, 'continue': 'gsroffset||'}}
        with patch.object(readers, '_seen_keys', return_value={'commons:File:Already seen'}), \
                patch.object(readers, '_api', side_effect=[first, raw]) as api, \
                patch.object(readers, '_image', return_value={'file': 'image.jpg', 'alt_source': 'Painting'}):
            item = readers.commons({})[0]
        self.assertEqual(item['key'], 'commons:' + row['title'])
        self.assertEqual(api.call_args.kwargs['gsroffset'], 10)

    def test_gutenberg_catalogue_is_cached_and_book_is_a_file(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, PIPELINE_HOME=folder), \
                patch.object(readers, '_download', side_effect=[(DATA / 'gutenberg.csv').read_bytes(),
                                                               (DATA / 'gutenberg.epub').read_bytes(),
                                                               (DATA / 'gutenberg.epub').read_bytes()]) as download:
            first = readers.gutenberg({'id': '14474'})[0]
            second = readers.gutenberg({'id': '14474'})[0]
            self.assertTrue(Path(first['file']).is_file())
            self.assertEqual(first['key'], second['key'])
            self.assertIsNone(first['media'])
            self.assertEqual(sum('pg_catalog.csv' in c.args[0] for c in download.call_args_list), 1)

    def test_gutenberg_unknown_rights_is_not_public_domain(self):
        # Metadata only: no book contents enter this fixture.
        import io
        import zipfile
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('package.opf', '<package xmlns:dc="http://purl.org/dc/elements/1.1/">'
                              '<dc:rights>Copyrighted work.</dc:rights></package>')
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, PIPELINE_HOME=folder), \
                patch.object(readers, '_download', side_effect=[(DATA / 'gutenberg.csv').read_bytes(), output.getvalue()]):
            self.assertEqual(readers.gutenberg({'id': '14474'}), [])

    def test_arxiv_saved_response(self):
        with patch.object(readers, 'get', return_value=(DATA / 'arxiv.xml').read_bytes()):
            item = readers.arxiv({})[0]
        self.assertEqual(item['kind'], 'paper')
        self.assertEqual(item['details']['paper_status'], 'preprint')
        self.assertTrue(item['text'])
        self.assertEqual(item['license'], 'CC0')

    def test_news_short_description_is_skipped(self):
        with patch.object(readers, 'get', return_value=json.dumps({'results': [
            {'article_id': 'short', 'title': 'Short', 'description': 'Too short.'}]}).encode()), \
                patch.object(readers.settings, 'secrets', return_value={'NEWSDATA_API_KEY': 'test'}):
            self.assertEqual(readers.newsdata({}), [])

    def test_image_signatures(self):
        for raw, ext in [(b'\xff\xd8\xff', '.jpg'), (b'\x89PNG\r\n\x1a\n', '.png'),
                         (b'RIFFxxxxWEBP', '.webp')]:
            self.assertEqual(readers.image_extension(raw), ext)
        with self.assertRaises(ValueError):
            readers.image_extension(b'<html>not an image</html>')

    def test_newsdata_saved_fields_and_credit(self):
        with patch.object(readers, 'get', return_value=(DATA / 'newsdata.json').read_bytes()), \
                patch.object(readers.settings, 'secrets', return_value={'NEWSDATA_API_KEY': 'test'}):
            item = readers.newsdata({})[0]
        self.assertTrue(item['details']['newspaper'])
        self.assertTrue(item['credit'].endswith('News data by NewsData.io.'))
        self.assertGreaterEqual(len(item['text'].split()), 40)

    def test_currents_saved_response_filters_short_items_and_keeps_publisher(self):
        from . import licenses
        with patch.object(readers, 'get', return_value=(DATA / 'currents.json').read_bytes()) as get, \
                patch.object(readers.settings, 'secrets', return_value={'CURRENTS_API_KEY': 'test'}):
            items = readers.currents({'category': 'technology'})
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertTrue(item['key'].startswith('currents:'))
        self.assertEqual(item['kind'], 'news')
        self.assertEqual(item['details']['newspaper'], 'macrumors.com')
        self.assertNotEqual(item['details']['newspaper'], item['credit'])
        self.assertEqual(item['license'], licenses.CURRENTS)
        self.assertEqual(item['published_on'], '2026-11-16')
        self.assertEqual(item['details']['show_until'], '2026-12-16')
        self.assertIn('currentsapi.services', item['credit'])
        self.assertIn('category=technology', get.call_args.args[0])
        self.assertEqual(get.call_args.args[1]['Authorization'], 'Bearer test')
        self.assertNotIn('test', get.call_args.args[0].split('?', 1)[1])

    def test_currents_missing_key_and_api_error_are_reported(self):
        with patch.object(readers.settings, 'secrets', return_value={}):
            with self.assertRaisesRegex(ValueError, 'CURRENTS_API_KEY'):
                readers.currents({})
        with patch.object(readers.settings, 'secrets', return_value={'CURRENTS_API_KEY': 'test'}), \
                patch.object(readers, 'get', return_value=b'{"status":"error","msg":"private"}'):
            with self.assertRaisesRegex(ValueError, 'Currents API'):
                readers.currents({})

    def test_ec_full_text_not_truncated_rss(self):
        with patch.object(readers, 'get', side_effect=[(DATA / 'ec.xml').read_bytes(),
                                                       (DATA / 'ec_full.json').read_bytes()]):
            item = readers.ec_press({'limit': 1})[0]
        self.assertIn('Merger Regulation', item['text'])
        self.assertEqual(item['license'], 'CC BY 4.0')

    def test_hf_only_selects_arxiv_ids(self):
        with patch.object(readers, 'get', return_value=(DATA / 'hf.json').read_bytes()), \
                patch.object(readers, 'arxiv', return_value=[]) as arxiv:
            readers.hf_daily_papers({'limit': 1})
        self.assertEqual(arxiv.call_args.args[0]['id'], '2611.12068')

    def test_europepmc_nd_never_downloads_full_text(self):
        raw = json.loads((DATA / 'epmc.json').read_bytes())
        raw['resultList']['result'][0]['license'] = 'CC BY-ND 4.0'
        with patch.object(readers, 'get', return_value=json.dumps(raw).encode()) as get:
            item = readers.europepmc({})[0]
        self.assertEqual(get.call_count, 1)
        self.assertIn('Dengue', item['text'])

    def test_met_checks_work_license_not_search_flag(self):
        row = json.loads((DATA / 'met.json').read_bytes())
        row['isPublicDomain'] = False
        with patch.object(readers, 'get', return_value=json.dumps(row).encode()), \
                patch.object(readers, '_image') as image:
            self.assertEqual(readers.met({'id': 436524}), [])
        image.assert_not_called()

    def test_met_public_work_downloads_image(self):
        with patch.object(readers, 'get', return_value=(DATA / 'met.json').read_bytes()), \
                patch.object(readers, '_image', return_value={'file': 'work.jpg', 'alt_source': 'Painting'}):
            item = readers.met({'id': 436524})[0]
        self.assertEqual(item['license'], 'CC0')
        self.assertTrue(item['text'])
        self.assertEqual(item['media']['file'], 'work.jpg')

    def test_met_skips_seen_before_object_or_image_download(self):
        with patch.object(readers, '_api', return_value={'objectIDs': [1, 436524]}), \
                patch.object(readers, '_seen_keys', return_value={'met:1'}), \
                patch.object(readers, '_json', return_value=json.loads((DATA / 'met.json').read_bytes())) as get, \
                patch.object(readers, '_image', return_value={'file': 'work.jpg', 'alt_source': 'Painting'}) as image:
            item = readers.met({})[0]
        self.assertEqual(item['key'], 'met:436524')
        get.assert_called_once_with('https://collectionapi.metmuseum.org/public/collection/v1/objects/436524')
        self.assertEqual(image.call_count, 1)

    def test_europepmc_full_body(self):
        with patch.object(readers, 'get', side_effect=[(DATA / 'epmc.json').read_bytes(),
                                                       (DATA / 'epmc.xml').read_bytes()]):
            item = readers.europepmc({})[0]
        self.assertIn('Dengue', item['text'])
        self.assertTrue(item['details']['doi'])

    def test_image_cached_after_first_download(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, PIPELINE_HOME=folder), \
                patch.object(readers, '_download', return_value=b'\xff\xd8\xffimage') as download:
            readers._image('https://example.org/image', 'First description')
            result = readers._image('https://example.org/image', 'Updated description')
        self.assertEqual(download.call_count, 1)
        self.assertEqual(result['alt_source'], 'Updated description')

    def test_get_redacts_secret_url_from_error(self):
        with patch.object(readers, 'urlopen', side_effect=OSError('https://host/?apikey=secret')), \
                patch.object(readers.time, 'sleep'), patch.object(readers.settings, 'secrets', return_value={}):
            with self.assertRaises(ValueError) as error:
                readers.get('https://host/?apikey=secret')
        self.assertNotIn('secret', str(error.exception))

    def test_get_does_not_forward_authorization_on_redirect(self):
        from unittest.mock import MagicMock
        from urllib.request import HTTPRedirectHandler
        response = MagicMock()
        response.__enter__.return_value.headers = {}
        response.__enter__.return_value.read.return_value = b'OK'
        with patch.object(readers, 'urlopen', return_value=response) as get, \
                patch.object(readers.time, 'sleep'):
            readers.get('https://api.currentsapi.services/', {'Authorization': 'Bearer secret'})
        request = get.call_args.args[0]
        self.assertEqual(request.get_header('Authorization'), 'Bearer secret')
        redirected = HTTPRedirectHandler().redirect_request(request, None, 302, '', {}, 'https://other.example/')
        self.assertFalse(redirected.has_header('Authorization'))

    def test_expired_request_budget_never_opens_network(self):
        with readers.request_budget(0), patch.object(readers, 'urlopen') as get:
            with self.assertRaises(TimeoutError):
                readers.get('https://example.org')
        get.assert_not_called()

    def test_europepmc_med_link_dispatch(self):
        with patch.object(readers, 'europepmc', return_value=[{'key': 'pmc'}]) as read:
            self.assertEqual(readers.from_url('https://europepmc.org/article/MED/42685739')['key'], 'pmc')
        self.assertEqual(read.call_args.args[0]['query'], 'EXT_ID:42685739 AND SRC:MED')

    def test_get_timeout_and_text_size_bound(self):
        from unittest.mock import MagicMock
        response = MagicMock()
        response.headers = {}
        response.read.return_value = b'OK'
        response.__enter__.return_value = response
        with patch.object(readers, 'urlopen', return_value=response) as get, \
                patch.object(readers.time, 'sleep'), patch.object(readers.settings, 'secrets', return_value={}):
            self.assertEqual(readers.get('https://example.org'), b'OK')
        self.assertEqual(get.call_args.kwargs['timeout'], 30)
        response.read.assert_called_once_with(5 * 1024 * 1024 + 1)

    def test_unknown_link_fetched_once_has_unknown_license(self):
        with patch.object(readers, 'get', return_value=b'<p>Public page.</p>') as get:
            item = readers.from_url('https://example.org/article')
        self.assertEqual(get.call_count, 1)
        self.assertEqual(item['license'], 'unknown')
        self.assertEqual(item['text'], 'Public page.')


if __name__ == '__main__':
    unittest.main()
