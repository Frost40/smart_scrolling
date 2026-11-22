"""Offline clock, publish and single-trial cleanup checks."""
from contextlib import closing
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from . import cardmaker, settings, store, stages


class StageTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()
        # Exercise scheduling without contacting the live request database.
        builtin = patch.dict(stages.BUILTINS, {'requests': lambda config, deadline: ('nothing', 'no open requests')})
        builtin.start()
        self.addCleanup(builtin.stop)

    def rows(self):
        with closing(store.connect()) as db:
            return [dict(r) for r in db.execute('SELECT * FROM runs')]

    def test_due_hours_pause_and_unbuilt(self):
        for name in stages.ORDER:
            settings.set_value(f'stages.{name}.enabled', 'false')
        settings.set_value('stages.requests.enabled', 'true')
        settings.set_value('stages.requests.hours', '[0,24]')
        stages.tick()
        self.assertEqual([(r['result'], r['summary']) for r in self.rows()], [('nothing', 'no open requests')])
        stages.tick()
        self.assertEqual(len(self.rows()), 1)
        settings.set_value('paused', 'true')
        stages.tick('requests')
        self.assertEqual(len(self.rows()), 1)
        settings.set_value('paused', 'false')
        settings.set_value('stages.requests.hours', '[0,0]')
        with closing(store.connect()) as db, db:
            db.execute('DELETE FROM runs')
        stages.tick()
        self.assertEqual(self.rows(), [])
        stages.tick('requests')
        self.assertEqual(len(self.rows()), 1)

    def test_live_and_stale_lock(self):
        with stages.tick_lock():
            stages.tick('requests')
            self.assertEqual(self.rows(), [])
        # A crash leaves the file but releases the operating system lock.
        (self.home / 'state/tick.lock').write_text('99999999')
        stages.tick('requests')
        self.assertEqual(len(self.rows()), 1)

    def test_external_command(self):
        import sys
        settings.set_value('stages.scout.run', json.dumps([sys.executable, '-c',
                           'import os; print(os.environ["PIPELINE_HOME"])']))
        stages.tick('scout')
        self.assertEqual(self.rows()[0]['result'], 'ok')
        self.assertIn(str(self.home), next((self.home / 'logs').glob('*.log')).read_text())

    def test_order_and_total_deadline(self):
        for name in stages.ORDER:
            settings.set_value(f'stages.{name}.hours', '[0,24]')
        with patch.object(stages, 'execute') as execute:
            stages.tick()
            self.assertEqual([c.args[0] for c in execute.call_args_list], list(stages.ORDER))
        with patch.object(stages.time, 'monotonic', side_effect=[0, 10000]), patch.object(stages, 'execute') as execute:
            stages.tick()
            execute.assert_not_called()

    def test_make_oldest_and_deadline(self):
        with closing(store.connect()) as db, db:
            db.executemany('INSERT INTO jobs(id,status,created_at) VALUES(?,?,?)',
                           [('new', 'queued', '2026-02-01'), ('old', 'waiting', '2026-01-01')])
        with patch.object(cardmaker, 'run', return_value='queued') as run:
            self.assertEqual(stages.make(settings.load(), 123), ('stopped', 'old: queued'))
            run.assert_called_once_with('old', deadline=123)

    def test_invalid_schedules_rejected_without_writing(self):
        for key, value in [('stages.make.hours', '[24,0]'), ('stages.make.hours', '[true,24]'),
                           ('stages.make.every_minutes', '0'), ('stages.make.run', '[]'),
                           ('dashboard.port', '65536')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                settings.set_value(key, value)
        self.assertFalse((self.home / 'settings.json').exists())

    def job(self):
        folder = self.home / 'jobs/trial-proof'
        (folder / 'source/trial-proof').mkdir(parents=True)
        source = {'id': 'trial-proof', 'title': 'Proof', 'status': 'draft', 'is_sample': True,
                  'discover_cards': [{'id': 'one'}], 'practice_cards': [{'id': 'test'}]}
        cardmaker.save(folder / 'source/trial-proof/source.json', source)
        for name in ('report', 'brief', 'ideas'):
            cardmaker.save(folder / f'{name}.json', {})
        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO jobs (id,status,created_at) VALUES ('trial-proof','ready',?)", (cardmaker.now(),))
        return folder

    def test_publish_failures_preserve_files_and_success_archives(self):
        for failure in ('dry-run', 'counts', 'archive', None):
            with self.subTest(failure=failure):
                folder = self.job() if not (self.home / 'jobs/trial-proof').exists() else self.home / 'jobs/trial-proof'
                cardmaker.update_job('trial-proof', status='ready')
                client = MagicMock()
                client.select.side_effect = lambda table, query: ([] if query.startswith('select=id,is_sample&') or (failure == 'counts' and table == 'discover_cards') else [{'id': 'x'}])
                command = MagicMock(returncode=1 if failure == 'dry-run' else 0, stdout='output', stderr='')
                copier = patch.object(stages.shutil, 'copy2', side_effect=OSError('disk full')) if failure == 'archive' else patch.object(stages, 'log')
                with patch.object(stages.upload, 'Supabase', return_value=client), \
                        patch.object(stages.subprocess, 'run', return_value=command), copier:
                    result, _ = stages.publish(settings.load(), float('inf'))
                self.assertEqual(result, 'failed' if failure else 'ok')
                self.assertEqual(folder.exists(), bool(failure))
        self.assertEqual(sorted(p.name for p in (self.home / 'archive/trial-proof').iterdir()),
                         ['brief.json', 'ideas.json', 'report.json'])

    def test_remove_trial_guards_and_scoped_deletion(self):
        client = MagicMock()
        with patch.object(stages.upload, 'Supabase', return_value=client):
            with self.assertRaises(ValueError):
                stages.remove_trial('real-source')
            client.select.return_value = [{'id': 'trial-proof', 'is_sample': False}]
            with self.assertRaises(ValueError):
                stages.remove_trial('trial-proof')
            client.delete.assert_not_called()
            client.select.return_value = [{'id': 'trial-proof', 'is_sample': True}]
            client.list_files.side_effect = lambda bucket, prefix: [prefix + '/one']
            stages.remove_trial('trial-proof')
            self.assertEqual(client.call.call_count, 3)
            client.delete.assert_called_once_with('sources', 'id=eq.trial-proof&is_sample=eq.true')

    def test_publish_resume_never_reuploads_existing_real_source(self):
        folder = self.job()
        client = MagicMock()
        client.select.return_value = [{'id': 'trial-proof', 'is_sample': False}]
        with patch.object(stages.upload, 'Supabase', return_value=client), \
                patch.object(stages.subprocess, 'run') as command:
            result, _ = stages.publish(settings.load(), float('inf'))
            self.assertEqual(result, 'failed')
            command.assert_not_called()
            self.assertTrue(folder.exists())
            cardmaker.update_job('trial-proof', status='ready', step='upload')
            outcome, message = stages.publish(settings.load(), float('inf'))
            self.assertEqual(outcome, 'failed')
            self.assertIn('interrupted upload', message)
            self.assertTrue(folder.exists())
            command.assert_not_called()
            cardmaker.update_job('trial-proof', status='ready', step='verify')
            with patch.object(stages.shutil, 'copy2', side_effect=OSError('disk full')):
                self.assertEqual(stages.publish(settings.load(), float('inf'))[0], 'failed')
            self.assertEqual(stages.rows('SELECT status,step FROM jobs')[0], {'status': 'uploaded', 'step': 'clean'})
            self.assertTrue(folder.exists())
            self.assertEqual(stages.publish(settings.load(), float('inf'))[0], 'ok')
            command.assert_not_called()
            self.assertFalse(folder.exists())

    def test_publish_recovers_deletion_before_done_update(self):
        self.job()
        cardmaker.update_job('trial-proof', status='uploaded', step='clean', counts='{"cards":1,"tests":1}')
        config = settings.load()
        config['publish']['keep_archive'] = False
        stages.shutil.rmtree(self.home / 'jobs/trial-proof')
        client = MagicMock()
        client.select.return_value = [{'id': 'one'}]
        with patch.object(stages.upload, 'Supabase', return_value=client), patch.object(stages.subprocess, 'run') as command:
            self.assertEqual(stages.publish(config, float('inf'))[0], 'ok')
            command.assert_not_called()
        self.assertEqual(stages.rows('SELECT status FROM jobs')[0]['status'], 'done')
