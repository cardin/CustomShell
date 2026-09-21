#!/usr/bin/env python3

"""Focused tests for the shared archive core used by both platforms."""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "archive_core.py"
MODULE_SPEC = importlib.util.spec_from_file_location("archive_core", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"cannot load archive core from {MODULE_PATH}")
archive_core = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(archive_core)


class ArchiveCoreTests(unittest.TestCase):
    def test_tarignore_path_patterns_are_anchored_to_their_directory(self) -> None:
        rules = [("", "logs/*.log"), ("sub", "nested/deep.bin")]

        self.assertTrue(archive_core.is_tarignored("logs/one.log", rules))
        self.assertFalse(archive_core.is_tarignored("sub/logs/one.log", rules))
        self.assertTrue(archive_core.is_tarignored("sub/nested/deep.bin", rules))
        self.assertFalse(archive_core.is_tarignored("nested/deep.bin", rules))

    def test_tarignore_basename_patterns_match_at_any_depth(self) -> None:
        rules = [("", "*.tmp")]

        self.assertTrue(archive_core.is_tarignored("a.tmp", rules))
        self.assertTrue(archive_core.is_tarignored("sub/deep/a.tmp", rules))
        self.assertFalse(archive_core.is_tarignored("a.txt", rules))

    def test_trailing_slash_pattern_is_not_supported(self) -> None:
        # A trailing slash is kept literally, matching the Windows translation,
        # so "cache/" does not match a directory named "cache".
        rules = [("", "cache/")]

        self.assertFalse(archive_core.is_tarignored("cache", rules))
        self.assertFalse(archive_core.is_tarignored("nested/cache", rules))

    def test_exclude_patterns_follow_tar_semantics(self) -> None:
        self.assertTrue(archive_core.is_excluded("node_modules", ("node_modules",)))
        self.assertTrue(archive_core.is_excluded("sub/node_modules", ("node_modules",)))
        self.assertTrue(archive_core.is_excluded("a.log", ("*.log",)))
        self.assertTrue(archive_core.is_excluded("sub/a.log", ("*.log",)))
        self.assertTrue(archive_core.is_excluded("logs/one.log", ("logs/*.log",)))
        self.assertFalse(archive_core.is_excluded("sub/logs/one.log", ("logs/*.log",)))
        self.assertFalse(archive_core.is_excluded("keep.txt", ("node_modules",)))

    def test_unreadable_tarignore_fails_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = pathlib.Path(temporary_directory)
            (source / ".tarignore").write_text("*.secret\n", encoding="utf-8")
            (source / "data.txt").write_text("data\n", encoding="utf-8")

            with mock.patch.object(
                pathlib.Path, "open", side_effect=OSError("permission denied")
            ):
                with self.assertRaises(OSError):
                    archive_core.collect_source_paths(source)

    def test_normalized_member_path_rejects_unsafe_paths(self) -> None:
        for path in ("", "/absolute", "C:/drive", "../escape", "top/../escape"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                archive_core.normalized_member_path(path)

    def test_windows_name_validation_rejects_reserved_names(self) -> None:
        for name in ("CON", "nul.txt", "bad:name", "trailing.", "trailing "):
            with self.subTest(name=name), self.assertRaises(ValueError):
                archive_core.validate_windows_name(name)

    def test_validate_destination_rejects_protected_and_invalid_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            home = root / "home"
            repository = root / "repo"
            parent = root / "parent"
            home.mkdir()
            repository.mkdir()
            parent.mkdir()
            valid = parent / "dest"

            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(
                    archive_core.validate_destination(
                        str(valid), str(home), str(repository)
                    ),
                    0,
                )
            self.assertEqual(output.getvalue().strip(), str(valid.resolve()))

            file_path = parent / "file.txt"
            file_path.write_text("x", encoding="utf-8")
            link = parent / "link"
            link.symlink_to(parent / "dest", target_is_directory=True)

            for candidate in (
                root.anchor,
                str(home),
                str(repository),
                str(parent / "missing" / "dest"),
                str(file_path),
                str(link),
            ):
                with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                    archive_core.validate_destination(
                        candidate, str(home), str(repository)
                    )

    def test_resolve_output_names_and_guards_the_output_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            source = root / "source"
            source.mkdir()
            (source / "data.txt").write_text("x", encoding="utf-8")

            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(archive_core.resolve_output(str(source)), 0)
            self.assertRegex(
                pathlib.Path(output.getvalue().strip()).name,
                r"^source_\d{8}_\d{6}\.enc$",
            )

            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(
                    archive_core.resolve_output(str(source), str(root / "backup")),
                    0,
                )
            self.assertRegex(
                pathlib.Path(output.getvalue().strip()).name,
                r"^backup_\d{8}_\d{6}\.enc$",
            )

            with self.assertRaises(ValueError):
                archive_core.resolve_output(str(source), str(source / "nested"))
            with self.assertRaises(ValueError):
                archive_core.resolve_output(
                    str(source), str(root / "absent" / "deep" / "out")
                )
            with self.assertRaises(ValueError):
                archive_core.resolve_output(root.anchor)


if __name__ == "__main__":
    unittest.main()
