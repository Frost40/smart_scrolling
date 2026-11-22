"""A collection description goes through the normal gates, judge and tests."""
import os
import tempfile
import unittest
from unittest.mock import patch

from . import cardmaker, feeds, gates, licenses, llm, settings


class ImageTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()
        settings.set_value('trial', 'true')
        self.image = self.home / 'state/image.png'
        self.picture_bytes = b'\x89PNG\r\n\x1a\n' + b'public test image'
        self.image.write_bytes(self.picture_bytes)
        self.item = {'key': 'met:1', 'kind': 'other', 'title': 'A garden', 'authors': [],
                     'published_on': '', 'link': 'https://www.metmuseum.org/art/collection/search/1',
                     'license': 'CC0', 'credit': 'The Met', 'details': {}, 'topics': ['culture'],
                     'text': 'A garden scene shows a red bridge above the pond. The work is an oil painting on canvas.',
                     'media': {'file': str(self.image), 'alt_source':
                               'A garden scene shows a red bridge above the pond. The work is an oil painting on canvas.'}}
        self.calls = []

    def answer(self, role, name, values, **kwargs):
        self.calls.append((role, name, values))
        if name == 'image':
            data = {'cards': [{'ref': 'image:1', 'title': 'Bridge over a pond',
                               'front': 'A red bridge crosses a garden pond.',
                               'back': 'Oil paint on canvas captures the garden view.',
                               'media_alt': 'A red bridge stands over a pond in a garden.'}]}
        elif name == 'judge':
            self.assertIn('media_alt:', str(values))
            data = {'verdicts': [{'ref': 'image:1', **dict.fromkeys(cardmaker.SIX, True), 'problem': '', 'fix': ''}]}
        elif name == 'quiz':
            data = {'tests': [{'card': 'image:1', 'type': 'flashcard', 'prompt': 'What colour is the bridge?',
                              'answer': 'Red.', 'explanation': 'The bridge is red.'},
                             {'card': 'image:1', 'type': 'true_false', 'prompt': 'The bridge is red.',
                              'is_true': True, 'explanation': 'The bridge is red.'}]}
        elif name == 'solve':
            data = {'unclear': [], 'answers': [{'test': 'image:1-flash', 'answerable': True, 'text': 'Red.'},
                                              {'test': 'image:1-tf', 'answerable': True, 'is_true': True}]}
        else:
            self.fail('image should reuse the judge/quiz/solve path, unexpected ' + name)
        return {'ok': True, 'provider': 'claude-haiku', 'data': data}

    def test_picture_is_judged_quizzed_packed_and_credited(self):
        job_id = feeds.enqueue(self.item, ['culture'])
        with patch.object(llm, 'call', side_effect=self.answer):
            self.assertEqual(cardmaker.run(job_id), 'ready')
        folder = self.home / 'jobs' / job_id / 'source' / job_id
        source = cardmaker.load(folder / 'source.json')
        card = source['discover_cards'][0]
        self.assertEqual(card['format'], 'image')
        self.assertEqual(card['media_alt'], 'A red bridge stands over a pond in a garden.')
        self.assertEqual((folder / card['media']).read_bytes(), self.picture_bytes)
        self.assertFalse(self.image.exists())
        self.assertEqual(licenses.source_license(source['description']), 'CC0')
        self.assertTrue(source['is_sample'])
        self.assertEqual(len(source['practice_cards']), 2)
        gates.upload.validate([(str(folder), source)], gates.known_topics(), check_files=True)

    def test_html_picture_and_unsupported_alt_are_refused(self):
        self.image.write_bytes(b'<html>access denied</html>')
        with self.assertRaises(ValueError):
            feeds.enqueue(self.item, ['culture'])
        card = {'format': 'image', 'title': 'A bridge', 'front': 'A red bridge spans a pond.',
                'back': 'The garden scene is painted on canvas.', 'level': 'intro',
                'media': 'image.png', 'media_alt': 'A bridge built in 999 stands in a garden.'}
        problems = gates.card_gates(card, None, self.item['text'], self.item['text'])
        self.assertIn('media_alt number 999', ' '.join(problems))


if __name__ == '__main__':
    unittest.main()
