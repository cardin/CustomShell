#!/usr/bin/env python3

"""Focused tests for the Linux archive path validator."""

import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "commands" / "archive_auth.py"
MODULE_SPEC = importlib.util.spec_from_file_location("archive_auth", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"cannot load archive validator from {MODULE_PATH}")
archive_auth = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(archive_auth)


class ArchiveAuthTests(unittest.TestCase):
    def test_trailing_slash_rule_matches_gnu_tar_behavior(self) -> None:
        rules = [("", "cache/")]

        self.assertFalse(archive_auth.is_tarignored("cache", rules))
        self.assertFalse(archive_auth.is_tarignored("nested/cache", rules))

    def test_unreadable_tarignore_fails_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = pathlib.Path(temporary_directory)
            (source / ".tarignore").write_text("*.secret\n", encoding="utf-8")
            (source / "data.txt").write_text("data\n", encoding="utf-8")

            with mock.patch.object(
                pathlib.Path, "open", side_effect=OSError("permission denied")
            ):
                with self.assertRaises(OSError):
                    archive_auth.collect_source_paths(source)

    def test_normalized_member_path_rejects_unsafe_paths(self) -> None:
        for path in ("", "/absolute", "C:/drive", "../escape", "top/../escape"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                archive_auth.normalized_member_path(path)

    def test_windows_name_validation_rejects_reserved_names(self) -> None:
        for name in ("CON", "nul.txt", "bad:name", "trailing.", "trailing "):
            with self.subTest(name=name), self.assertRaises(ValueError):
                archive_auth.validate_windows_name(name)


if __name__ == "__main__":
    unittest.main()
