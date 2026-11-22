"""Offline license, intake, counters and link checks."""
from contextlib import closing
import json
import os
import tempfile
import unittest
from unittest.mock import patch

from . import cardmaker, settings, store


class FeedTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()
        settings.set_value('trial', 'true')
        self.feed = {'reader': 'arxiv', 'params': {'query': 'cat:cs.AI'},
                     'topics': ['artificial-intelligence'], 'per_day': 1, 'enabled': True}
        self.item = {'key': 'arxiv:one', 'kind': 'paper', 'title': 'Attention and memory',
                     'authors': ['Test Author'], 'published_on': '2026-11-15',
                     'link': 'https://arxiv.org/abs/one', 'license': 'CC0', 'credit': 'arXiv',
                     'text': 'The study examines how attention affects the way people learn and remember.',
                     'details': {'paper_status': 'preprint'}, 'topics': [], 'media': None}

    def test_license_spellings_and_refusals(self):
        from . import licenses
        for name in ('CC BY 4.0', 'cc-by', 'CC-BY-SA-4.0', 'Public domain', 'PD', 'CC0 1.0',
                     'https://creativecommons.org/licenses/by/4.0/'):
            with self.subTest(name=name):
                self.assertTrue(licenses.allowed(name))
        for name in ('CC BY-ND 4.0', 'cc-by-nc-nd', 'unknown', 'all rights reserved', '',
                     'not CC BY', 'CC BY-SA 4.0 except photos'):
            with self.subTest(name=name):
                self.assertFalse(licenses.allowed(name))
        for name in ('CC BY-NC', 'CC-BY-NC-SA-4.0'):
            self.assertTrue(licenses.allowed(name))
            self.assertFalse(licenses.allowed(name, False))

    def test_stage_caps_seen_news_dates_and_persistent_counts(self):
        from . import feeds, readers
        config = settings.load()
        config['feeds'] = [self.feed]
        items = [self.item, {**self.item, 'key': 'arxiv:two', 'title': 'Another study',
                             'text': self.item['text'] + ' Learning changes with practice.'}]
        with patch.object(readers, 'arxiv', return_value=items):
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'ok')
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'nothing')
            config['feeds'][0]['per_day'] = 2
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'ok')
        self.assertEqual(feeds.stats(config)[0]['today'], 2)
        self.assertEqual(feeds.stats(config)[0]['total'], 2)
        with closing(store.connect()) as db:
            jobs = list(db.execute('SELECT * FROM jobs'))
        self.assertEqual(len(jobs), 2)
        for job in jobs:
            self.assertTrue(job['id'].startswith('trial-'))
            meta = cardmaker.load(self.home / 'jobs' / job['id'] / 'meta.json')
            self.assertTrue(meta['sample'])
            self.assertEqual(meta['topics'], self.feed['topics'])
            self.assertTrue((self.home / 'jobs' / job['id'] / 'text.txt').exists())
        news = {**self.item, 'key': 'news:one', 'kind': 'news', 'title': 'News item',
                'details': {'newspaper': 'Wikipedia Current events'}}
        job_id = feeds.enqueue(news, ['society'])
        meta = cardmaker.load(self.home / 'jobs' / job_id / 'meta.json')
        self.assertEqual(meta['details']['show_until'], '2026-12-15')
        self.assertTrue((self.home / 'jobs' / job_id / 'text.txt').read_text().startswith('Published on 2026-11-15.'))

    def test_currents_scope_label_survives_intake_and_obeys_noncommercial_switch(self):
        from . import feeds, licenses, readers
        config = settings.load()
        feed = next(f for f in config['feeds'] if f['reader'] == 'currents')
        self.assertTrue(feed['enabled'])
        config['feeds'] = [feed]
        item = {**self.item, 'key': 'currents:one', 'kind': 'news', 'license': licenses.CURRENTS,
                'credit': 'Publisher via Currents API (https://currentsapi.services/)',
                'details': {'newspaper': 'Publisher'}}
        self.assertTrue(licenses.allowed(item['license']))
        self.assertFalse(licenses.allowed(item['license'], False))
        self.assertEqual(licenses.source_license(licenses.attribution(item)), licenses.CURRENTS)
        with patch.object(readers, 'currents', return_value=[item]):
            config['licenses']['allow_noncommercial'] = False
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'nothing')
            config['licenses']['allow_noncommercial'] = True
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'ok')
        self.assertEqual(feeds.stats(config)[0]['total'], 1)

    def test_refused_licenses_failure_and_overview_warning(self):
        from . import dashboard, feeds, readers
        config = settings.load()
        config['feeds'] = [self.feed]
        with patch.object(readers, 'arxiv', return_value=[{**self.item, 'license': 'CC BY-ND 4.0'}]):
            self.assertEqual(feeds.stage(config, float('inf'))[0], 'nothing')
        self.assertEqual(feeds.stats(config)[0]['total'], 0)
        with patch.object(readers, 'arxiv', side_effect=ValueError('reader unavailable')):
            for _ in range(3):
                self.assertEqual(feeds.stage(config, float('inf'))[0], 'failed')
        self.assertIn('reader unavailable', feeds.stats(config)[0]['last_error'])
        self.assertEqual(feeds.stats(config)[0]['failures'], 3)
        with patch.object(settings, 'load', return_value=config):
            self.assertIn('3', dashboard.state()['stages']['feeds']['notice'])

    def test_unknown_link_requires_explicit_allowed_license(self):
        from . import feeds, readers
        item = {**self.item, 'kind': 'other', 'license': 'unknown'}
        with patch.object(readers, 'from_url', return_value=item):
            with self.assertRaisesRegex(ValueError, 'license'):
                feeds.add_link('https://example.org/article', sample=True)
            job = feeds.add_link('https://example.org/article', sample=True, license='CC BY 4.0')
        self.assertEqual(cardmaker.load(self.home / 'jobs' / job / 'meta.json')['license'], 'CC BY 4.0')

    def test_feed_settings_reject_unknown_reader_topic_and_invalid_cap(self):
        for change in ({'reader': 'made_up'}, {'topics': ['made_up']}, {'per_day': True},
                       {'per_day': -1}, {'enabled': 'yes'}, {'typo': 1}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                settings.set_value('feeds', json.dumps([{**self.feed, **change}]))

    def test_distinct_keys_with_identical_text_do_not_reuse_a_job(self):
        from . import feeds
        one = feeds.enqueue(self.item, ['artificial-intelligence'])
        two = feeds.enqueue({**self.item, 'key': 'arxiv:different'}, ['artificial-intelligence'])
        self.assertNotEqual(one, two)

    def test_inventory_reads_trailing_credit_and_marks_nc(self):
        from . import licenses
        rows = [{'id': 'first', 'kind': 'other', 'description': 'Adapted from Museum, CC-BY-NC-SA-4.0.'},
                {'id': 'second', 'kind': 'news', 'description': licenses.attribution({
                    'license': licenses.NEWSDATA, 'credit': 'Publisher', 'details': {'newspaper': 'Publisher'}})},
                {'id': 'third', 'kind': 'book', 'description': 'A story about CC BY.'},
                {'id': 'fourth', 'kind': 'news', 'description': licenses.attribution({
                    'license': licenses.CURRENTS, 'credit': 'Publisher via Currents API'})}]
        with patch.object(licenses.upload, 'Supabase') as client:
            client.return_value.select.side_effect = [rows[:2], rows[2:], []]
            result = list(licenses.inventory())
        self.assertIn('offset=2', client.return_value.select.call_args_list[1].args[1])
        self.assertEqual([r['license'] for r in result],
                         ['CC BY-NC-SA 4.0', licenses.NEWSDATA, 'unknown', licenses.CURRENTS])
        self.assertEqual([r['noncommercial'] for r in result], [True, True, False, True])

    def test_failing_feed_does_not_block_the_next_feed_and_error_is_recorded(self):
        from . import feeds, readers, stages
        good = {**self.feed, 'reader': 'hf_daily_papers'}
        settings.set_value('feeds', json.dumps([self.feed, good]))
        with (patch.object(readers, 'arxiv', side_effect=ValueError('offline')),
              patch.object(readers, 'hf_daily_papers', return_value=[self.item])):
            self.assertEqual(stages.tick('feeds'), 'failed')
        self.assertEqual(feeds.stats()[1]['total'], 1)
        self.assertIn('arxiv: offline', stages.rows('SELECT summary FROM runs')[0]['summary'])

    def test_reader_deadline_stops_stage_without_creating_a_job(self):
        from . import feeds, readers
        config = settings.load()
        config['feeds'] = [self.feed]
        def expired(params):
            raise TimeoutError('budget exhausted')
        with patch.object(readers, 'arxiv', side_effect=expired), patch.object(feeds.time, 'monotonic', side_effect=[0, 11]):
            self.assertEqual(feeds.stage(config, 10)[0], 'stopped')
        self.assertEqual(feeds.stats(config)[0]['total'], 0)

    def test_paper_selection_uses_research_format(self):
        path = self.home / 'state/paper.txt'
        path.write_text(self.item['text'])
        job = cardmaker.Job(cardmaker.create(path, kind='paper'))
        idea = {'ref': '01:1', 'kind': 'research', 'title': 'A finding', 'claim': 'A finding.',
                'stance': 'claims', 'importance': 5, 'quote_text': '', 'speaker': ''}
        result = {'chosen': [{'ref': '01:1', 'format': 'concept', 'level': 'intro'}],
                  'duplicates': [], 'topics': ['artificial-intelligence'], 'new_topic': ''}
        with patch.object(job, 'ask', return_value={'data': result}):
            chosen, _ = cardmaker.select(job, {'thesis': 'A finding.'}, [idea], True)
        self.assertEqual(chosen[0]['format'], 'research')
        (job.folder / 'selection.json').unlink()
        with patch.object(job, 'ask') as ask:
            chosen, _ = cardmaker.select(job, {'thesis': 'A finding.'}, [{**idea, 'kind': 'concept'}], True)
        self.assertEqual(chosen, [])
        ask.assert_not_called()


if __name__ == '__main__':
    unittest.main()
