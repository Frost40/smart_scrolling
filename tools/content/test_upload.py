"""Tests for the upload tool's checks. Run: python -m unittest discover tools/content"""

import copy
import os
import unittest
from unittest.mock import MagicMock, patch

import upload

SAMPLE = os.path.join(upload.HERE, "sample")
TOPICS = {"psychology", "learning-and-memory", "habits", "neuroscience", "health", "mathematics", "society",
          "culture", "physics", "optics", "everyday-physics"}


def source(**changes):
    s = {"id": "my-book", "kind": "book", "title": "My book", "topics": ["psychology"],
         "discover_cards": [{"id": "idea", "format": "concept", "title": "An idea", "front": "Front"}],
         "practice_cards": [{"id": "idea-flash", "type": "flashcard", "prompt": "Q?", "answer": "A", "tests": ["idea"]}]}
    s.update(changes)
    return s


def check(s, known_cards=()):
    return upload.validate([(os.path.join("x", s["id"]), s)], TOPICS, set(known_cards), check_files=False)


def errors(s, known_cards=()):
    try:
        check(s, known_cards)
    except upload.Invalid as e:
        return str(e)
    return ""


class SampleBox(unittest.TestCase):
    def test_sample_box_is_valid_and_all_sample(self):
        batch = upload.load_folder(SAMPLE)
        plans = upload.validate(batch, TOPICS)
        self.assertEqual(len(plans), 5)
        self.assertEqual({p["kind"] for p in plans}, {"book", "paper", "news", "other"})
        self.assertTrue(all(p["source"]["is_sample"] for p in plans))
        types = {c["type"] for p in plans for c in p["practice"]}
        self.assertEqual(types, upload.TYPES)

    def test_three_samples_of_each_new_practice_type(self):
        plans = upload.validate(upload.load_folder(SAMPLE), TOPICS)
        for kind in ("true_false", "ordering", "matching"):
            self.assertGreaterEqual(sum(c["type"] == kind for p in plans for c in p["practice"]), 3)


class Ids(unittest.TestCase):
    def test_card_ids_get_the_source_id(self):
        plan = check(source())[0]
        self.assertEqual(plan["cards"][0]["id"], "my-book/idea")
        self.assertEqual(plan["links"], [{"discover_card_id": "my-book/idea", "practice_card_id": "my-book/idea-flash"}])

    def test_bad_ids(self):
        self.assertIn("source id", errors(source(id="My_Book")))
        bad_card = source(discover_cards=[{"id": "Idea 1", "format": "concept", "title": "t", "front": "f"}],
                          practice_cards=[])
        self.assertIn("card id must be", errors(bad_card))

    def test_folder_must_match_id(self):
        s = source()
        self.assertIn("folder name", str(self._raises(lambda: upload.validate([("x/other", s)], TOPICS, check_files=False))))

    def test_duplicate_card_id(self):
        card = {"id": "idea", "format": "concept", "title": "t", "front": "f"}
        self.assertIn("used twice", errors(source(discover_cards=[card, card])))

    def test_related_pairs_are_stored_smaller_first(self):
        cards = [{"id": "b", "format": "concept", "title": "t", "front": "f", "related": ["a"]},
                 {"id": "a", "format": "concept", "title": "t", "front": "f"}]
        plan = check(source(discover_cards=cards, practice_cards=[]))[0]
        self.assertEqual(plan["related"], [{"discover_card_id": "my-book/a", "related_card_id": "my-book/b"}])

    def _raises(self, f):
        with self.assertRaises(upload.Invalid) as ctx:
            f()
        return ctx.exception


class Rules(unittest.TestCase):
    def test_existing_storage_references(self):
        s = source(cover={'existing': 'sources/my-book/cover.jpg'})
        s['discover_cards'][0].update(format='image', media_alt='An image',
                                      media={'existing': 'cards/my-book/idea/image.png'})
        plan = upload.validate([('my-book', s)], TOPICS)[0]
        self.assertEqual(plan['files'], [])
        self.assertEqual(plan['source']['cover_path'], s['cover']['existing'])
        db = MagicMock()
        db.select.side_effect = lambda table, query: {
            'topics': [{'id': t} for t in TOPICS], 'sources': [plan['source']],
            'discover_cards': plan['cards'], 'practice_cards': plan['practice'],
        }.get(table, [])
        with patch.object(upload, 'Supabase', return_value=db), patch.object(upload, 'load_folder', return_value=[('my-book', s)]):
            upload.upload('my-book', True)
            upload.upload('my-book', False)
            db.put_file.assert_not_called()
            db.select.side_effect = lambda table, query: [{'id': t} for t in TOPICS] if table == 'topics' else []
            with self.assertRaisesRegex(upload.Invalid, 'not the currently attached'):
                upload.upload('my-book', True)
        for invalid in ({'existing': 'sources/other/cover.jpg'}, {'existing': '../cover.jpg'},
                        {'existing': 'https://example.com/cover.jpg'}, {'existing': 2},
                        {'existing': 'sources/my-book/cover.jpg', 'extra': True}):
            with self.subTest(invalid=invalid):
                self.assertTrue(errors(source(cover=invalid)))
        self.assertIsNone(check(source())[0]['source']['cover_path'])

    def test_links_must_point_at_known_cards(self):
        s = source(practice_cards=[{"id": "t", "type": "flashcard", "prompt": "Q", "answer": "A",
                                    "tests": ["other-source/card"]}])
        self.assertIn("tests unknown card", errors(s))
        self.assertEqual(errors(s, known_cards={"other-source/card"}), "")

    def test_unknown_topic(self):
        self.assertIn("unknown topic", errors(source(topics=["astrology"])))

    def test_details_must_match_kind(self):
        self.assertIn("only belong", errors(source(paper={"doi": "x"})))
        self.assertIn("pages", errors(source(book={"pages": 0})))

    def test_discover_rules(self):
        def card(**kw):
            return source(discover_cards=[{"id": "idea", "title": "t", "front": "f", **kw}])
        self.assertIn("speaker", errors(card(format="quote")))
        self.assertIn("media file", errors(card(format="image", media_alt="x")))
        self.assertIn("news source", errors(card(format="news")))
        self.assertIn("format must be", errors(card(format="poem")))
        self.assertIn("level must be", errors(card(format="concept", level="expert")))
        self.assertIn("must end in", errors(card(format="image", media="a.gif", media_alt="x")))

    def test_practice_rules(self):
        def test(**kw):
            return source(practice_cards=[{"id": "t", "prompt": "Q", "tests": ["idea"], **kw}])
        self.assertIn("answer", errors(test(type="flashcard")))
        self.assertIn("2 to 6", errors(test(type="multiple_choice", choices=["a"], correct_choice=0)))
        self.assertIn("correct_choice", errors(test(type="multiple_choice", choices=["a", "b"], correct_choice=2)))
        self.assertIn("is_true", errors(test(type="true_false")))
        self.assertIn("at least 2", errors(test(type="ordering", correct_order=["a"])))
        self.assertIn("as many right", errors(test(type="matching", match_left=["a", "b"], match_right=["x"])))
        self.assertIn("'tests'", errors(source(practice_cards=[{"id": "t", "type": "true_false", "prompt": "Q", "is_true": True}])))

    def test_files_go_to_fixed_paths(self):
        self.assertEqual(upload.bucket_path("cover", ".jpeg", "s"), ("media", "sources/s/cover.jpg"))
        self.assertEqual(upload.bucket_path("original", ".pdf", "s"), ("source-files", "s/original.pdf"))
        self.assertEqual(upload.bucket_path("media", ".mp4", "s", "s/c"), ("media", "cards/s/c/video.mp4"))
        self.assertEqual(upload.bucket_path("media", ".png", "s", "s/c"), ("media", "cards/s/c/image.png"))

    def test_missing_file_is_reported(self):
        s = source(cover="nope.png")
        with self.assertRaises(upload.Invalid) as ctx:
            upload.validate([(os.path.join(SAMPLE, "my-book"), s)], TOPICS)
        self.assertIn("file not found", str(ctx.exception))

    def test_changed_rows(self):
        old = [{"id": "a", "title": "x", "version": 3}, {"id": "b", "title": "y"}]
        new, upd = upload.changed([{"id": "a", "title": "x"}, {"id": "b", "title": "z"}, {"id": "c", "title": "w"}], old)
        self.assertEqual([r["id"] for r in new], ["c"])
        self.assertEqual([r["id"] for r in upd], ["b"])

    def test_topics_file(self):
        with open(os.path.join(upload.HERE, "topics.json"), encoding="utf-8") as f:
            topics = __import__("json").load(f)
        upload.validate_topics(topics)
        three_levels = copy.deepcopy(topics) + [{"id": "deep", "name": "Deep", "parent": "artificial-intelligence"}]
        with self.assertRaises(upload.Invalid):
            upload.validate_topics(three_levels)
        lonely = [t for t in topics if t.get("parent") != "computer-science" or t["id"] == "programming"]
        with self.assertRaisesRegex(upload.Invalid, "only sub-topic is 'programming'"):
            upload.validate_topics(lonely)


if __name__ == "__main__":
    unittest.main()
