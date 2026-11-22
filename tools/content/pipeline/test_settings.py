"""Settings and local store checks: python -m unittest tools.content.pipeline.test_settings."""

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.content.pipeline import settings, store


class PipelineHomeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "home"
        self.enterContext(patch.dict(os.environ, {"PIPELINE_HOME": str(self.folder)}))
        self.enterContext(patch.object(settings, "ROOT", self.root))

    def overlay(self, value):
        self.folder.mkdir(parents=True, exist_ok=True)
        (self.folder / "settings.json").write_text(json.dumps(value), encoding="utf-8")


class SettingsTests(PipelineHomeTest):
    def test_home_creates_only_documented_subfolders(self):
        self.assertEqual(settings.home(), self.folder)
        self.assertEqual(
            {p.name for p in self.folder.iterdir()},
            {"state", "inbox", "probe", "sandbox", "jobs", "archive", "logs"},
        )
        (self.folder / "inbox" / "keep.txt").write_text("keep", encoding="utf-8")
        settings.home()
        self.assertEqual((self.folder / "inbox" / "keep.txt").read_text(), "keep")

    def test_home_precedence_environment_then_dotenv_then_profile(self):
        dotenv_home = self.root / "from-dotenv"
        (self.root / ".env").write_text(f'PIPELINE_HOME="{dotenv_home}"\n', encoding="utf-8")
        self.assertEqual(settings.home(), self.folder)
        del os.environ["PIPELINE_HOME"]
        self.assertEqual(settings.home(), dotenv_home)
        (self.root / ".env").unlink()
        with patch.dict(os.environ, {"USERPROFILE": str(self.root)}):
            self.assertEqual(settings.home(), self.root / "SmartScrollingContent")

    def test_secrets_use_upload_parsing_and_ignore_process_values(self):
        (self.root / ".env").write_text(
            ' # COMMENT=ignored\nKEY = "one=two"\nSINGLE=\'quoted\'\n'
            'BARE=word # kept\nEMPTY=\nnot an assignment\nKEY="last"\n',
            encoding="utf-8",
        )
        with patch.dict(os.environ, {"KEY": "process"}):
            self.assertEqual(settings.secrets(), {
                "KEY": "last", "SINGLE": "'quoted'", "BARE": "word # kept", "EMPTY": "",
            })

    def test_home_does_not_discover_profile_when_userprofile_is_set(self):
        with patch.dict(os.environ, {"PIPELINE_HOME": "", "USERPROFILE": str(self.root)}):
            with patch.object(Path, "home", side_effect=RuntimeError("profile unavailable")):
                self.assertEqual(settings.home(), self.root / "SmartScrollingContent")

    def test_defaults_without_settings_or_secrets(self):
        loaded = settings.load()
        self.assertEqual(loaded["stages"]["fetch"]["every_minutes"], 120)
        self.assertEqual(loaded["roles"]["judge"], ["claude-sonnet", "claude-haiku"])
        self.assertFalse((self.folder / "settings.json").exists())

    def test_recursive_overlay_preserves_siblings_and_replaces_lists(self):
        self.overlay({"make": {"cards": {"book": {"min": 12}}},
                      "roles": {"judge": ["gemini-cli"]}, "paused": True})
        loaded = settings.load()
        self.assertEqual(loaded["make"]["cards"]["book"], {"per_words": 2500, "min": 12, "max": 60})
        self.assertEqual(loaded["roles"]["judge"], ["gemini-cli"])
        self.assertTrue(loaded["paused"])
        loaded["make"]["cards"]["book"]["max"] = 999
        self.assertEqual(settings.load()["make"]["cards"]["book"]["max"], 60)

    def test_unknown_paths_are_rejected_at_every_depth(self):
        for value, path in [
            ({"pausd": True}, "pausd"),
            ({"make": {"cards": {"book": {"mn": 12}}}}, "make.cards.book.mn"),
            ({"roles": {"typo": []}}, "roles.typo"),
            ({"providers": {"claude-haiku": {"enabeld": False}}}, "providers.claude-haiku.enabeld"),
            ({"providers": {"openrouter": {"extra_body": {"provider": {"typo": True}}}}},
             "providers.openrouter.extra_body.provider.typo"),
        ]:
            with self.subTest(path=path):
                self.overlay(value)
                with self.assertRaises(ValueError) as error:
                    settings.load()
                self.assertIn(path, str(error.exception))

    def test_optional_documented_fields_work_for_existing_providers(self):
        fields = {"enabled": False, "program": "/tmp/model", "tools": "on",
                  "base_url": "http://localhost/v1", "key_env": "CUSTOM_KEY", "json": "object",
                  "extra_body": {"provider": {"require_parameters": False}}}
        self.overlay({"providers": {"claude-haiku": fields}})
        loaded = settings.load()["providers"]["claude-haiku"]
        for key, value in fields.items():
            self.assertEqual(loaded[key], value)
        self.assertEqual(loaded["preset"], "claude")
        self.assertNotIn("program", settings.load()["providers"]["claude-sonnet"])

    def test_new_providers_and_feed_items_are_allowed(self):
        providers = {
            "custom-cli": {"driver": "cli", "preset": "claude", "model": "other"},
            "custom-api": {"driver": "openai", "base_url": "http://localhost/v1"},
        }
        feeds = [{"reader": "arxiv", "params": {"query": "cat:cs.AI"},
                  "topics": ["artificial-intelligence"], "per_day": 1, "enabled": True}]
        self.overlay({"providers": providers, "feeds": feeds})
        loaded = settings.load()
        self.assertEqual(loaded["feeds"], feeds)
        for key, value in providers.items():
            self.assertEqual(loaded["providers"][key], value)

    def test_new_provider_requires_driver_and_preset_or_base_url(self):
        for provider, path in [
            ({"preset": "claude"}, "providers.custom.driver"),
            ({"driver": "cli"}, "providers.custom"),
            ({"driver": "cli", "preset": ""}, "providers.custom"),
            ({"driver": "cli", "preset": "claude", "typo": True}, "providers.custom.typo"),
        ]:
            with self.subTest(provider=provider):
                self.overlay({"providers": {"custom": provider}})
                with self.assertRaises(ValueError) as error:
                    settings.load()
                self.assertIn(path, str(error.exception))

    def test_settings_and_dictionary_branches_must_be_objects(self):
        for value, path in [([], "settings"), ({"providers": []}, "providers"),
                            ({"providers": {"custom": "cli"}}, "providers.custom"),
                            ({"make": {"cards": None}}, "make.cards")]:
            with self.subTest(value=value):
                self.overlay(value)
                with self.assertRaises(ValueError) as error:
                    settings.load()
                self.assertIn(path, str(error.exception))

    def test_known_values_match_default_types_and_bool_is_not_a_number(self):
        for path, value in [
            ("paused", "true"), ("paused", 1), ("tick.max_minutes", True),
            ("tick.max_minutes", 2.5), ("tick.max_minutes", "3"),
            ("quality.min_pass_rate", False), ("quality.min_pass_rate", "0.8"),
            ("fetch.bot", 42), ("fetch.formats", "epub"), ("feeds", {}),
            ("roles.judge", "claude-haiku"), ("providers.claude-haiku.enabled", "false"),
            ("providers.claude-haiku.max_calls_per_day", True),
            ("providers.claude-haiku.program", []),
        ]:
            with self.subTest(path=path, value=value):
                with self.assertRaises(ValueError) as error:
                    settings.set_value(path, json.dumps(value))
                self.assertIn(path, str(error.exception))
                self.assertFalse((self.folder / "settings.json").exists())

    def test_roles_reject_unknown_or_non_string_providers(self):
        for names in [["missing-provider"], [5], [{}]]:
            with self.subTest(names=names):
                self.overlay({"roles": {"judge": names}})
                with self.assertRaises(ValueError) as error:
                    settings.load()
                self.assertIn("roles.judge", str(error.exception))
        self.overlay({"providers": {"custom": {"driver": "cli", "preset": "claude"}},
                      "roles": {"judge": ["custom"]}})
        self.assertEqual(settings.load()["roles"]["judge"], ["custom"])

    def test_stage_run_also_accepts_documented_command_lists(self):
        settings.set_value("stages.make.run", '["python", "custom.py"]')
        self.assertEqual(settings.load()["stages"]["make"]["run"], ["python", "custom.py"])

    def test_set_parses_json_and_roles_and_preserves_only_overrides(self):
        defaults_path = Path(settings.__file__).with_name("defaults.json")
        before = defaults_path.read_bytes()
        self.overlay({"tick": {"max_minutes": 4}})
        settings.set_value("roles.judge", "gemini-cli, claude-sonnet")
        settings.set_value("providers.claude-haiku.model", "custom-model")
        settings.set_value("paused", "true")
        settings.set_value("stages.fetch.every_minutes", "60")
        self.assertEqual(json.loads((self.folder / "settings.json").read_text()), {
            "tick": {"max_minutes": 4}, "roles": {"judge": ["gemini-cli", "claude-sonnet"]},
            "providers": {"claude-haiku": {"model": "custom-model"}}, "paused": True,
            "stages": {"fetch": {"every_minutes": 60}},
        })
        self.assertEqual(defaults_path.read_bytes(), before)
        settings.set_value("roles.judge", '["claude-haiku"]')
        self.assertEqual(settings.load()["roles"]["judge"], ["claude-haiku"])

    def test_set_can_add_a_complete_provider_and_optional_fields(self):
        settings.set_value("providers.new", '{"driver":"cli","preset":"claude"}')
        settings.set_value("providers.new.enabled", "false")
        self.assertFalse(settings.load()["providers"]["new"]["enabled"])

    def test_invalid_set_never_changes_the_existing_file(self):
        self.overlay({"paused": True})
        original = (self.folder / "settings.json").read_bytes()
        for path, value in [("tick.typo", "3"), ("providers.new", '{"model":"x"}'),
                            ("roles.typo", "claude-haiku"), ("tick..max_minutes", "3"), ("", "3")]:
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    settings.set_value(path, value)
                self.assertEqual((self.folder / "settings.json").read_bytes(), original)

    def test_invalid_set_does_not_create_a_settings_file(self):
        with self.assertRaises(ValueError):
            settings.set_value("typo", "true")
        self.assertFalse((self.folder / "settings.json").exists())

    def test_failed_atomic_replace_keeps_original_and_cleans_temp_file(self):
        self.overlay({"paused": False})
        original = (self.folder / "settings.json").read_bytes()
        with patch("os.replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                settings.set_value("paused", "true")
        self.assertEqual((self.folder / "settings.json").read_bytes(), original)
        self.assertEqual({p.name for p in self.folder.iterdir() if p.is_file()}, {"settings.json"})


class StoreTests(PipelineHomeTest):
    def test_exact_schema_and_reconnect_preserves_rows(self):
        expected = {
            "books": "id title authors year isbn13 ol_work topics origin score priority status attempts next_try_at last_error job_id added_at updated_at",
            "jobs": "id kind title origin status step attempts error counts created_at updated_at",
            "seen": "key job_id at",
            "runs": "id stage started_at ended_at result summary",
            "calls": "at provider role job_id ok error_kind seconds tokens_in tokens_out",
        }
        connection = store.connect()
        try:
            self.assertEqual({row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )}, set(expected))
            for table, columns in expected.items():
                self.assertEqual([row[1] for row in connection.execute(f"PRAGMA table_info({table})")], columns.split())
            for table, column in [("books", "authors"), ("books", "topics"), ("jobs", "counts"),
                                  ("calls", "at"), ("runs", "started_at")]:
                types = {row[1]: row[2] for row in connection.execute(f"PRAGMA table_info({table})")}
                self.assertEqual(types[column], "TEXT")
            connection.execute("INSERT INTO books (id, title, authors) VALUES (?, ?, ?)",
                               ("sample", "Sample", '["Author"]'))
            connection.commit()
        finally:
            connection.close()
        connection = store.connect()
        try:
            row = connection.execute("SELECT id, title, authors FROM books").fetchone()
            self.assertEqual(tuple(row), ("sample", "Sample", '["Author"]'))
            self.assertEqual(row["title"], "Sample")
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
