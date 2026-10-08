#!/usr/bin/env python3

"""Focused tests for the shared archive core used by both platforms."""

import contextlib
import importlib.util
import io
import os
import pathlib
import subprocess
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
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()

    def write(self, relative: str, content: str = "data\n") -> pathlib.Path:
        path = self.source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def collected(self, **options) -> set[str]:
        return {
            path.relative_to(self.source).as_posix()
            for path in archive_core.collect_source_paths(self.source, **options)
        }

    def git(self, *arguments) -> None:
        environment = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        subprocess.run(
            ["git", "-C", str(self.source), *arguments],
            env=environment, check=True, capture_output=True,
        )

    def test_gitignore_paths_basename_and_nested_precedence(self) -> None:
        self.write(".gitignore", "logs/*.log\n*.tmp\n/root.txt\n*.bin\n")
        self.write("sub/.gitignore", "!keep.bin\nnested/deep.txt\n")
        for name in (
            "logs/one.log", "sub/logs/one.log", "root.txt", "sub/root.txt",
            "a.tmp", "sub/deep/a.tmp", "sub/keep.bin", "sub/drop.bin",
            "sub/nested/deep.txt", "nested/deep.txt",
        ):
            self.write(name)
        included = self.collected()
        for name in ("sub/logs/one.log", "sub/root.txt", "sub/keep.bin", "nested/deep.txt"):
            self.assertIn(name, included)
        for name in ("logs/one.log", "root.txt", "a.tmp", "sub/deep/a.tmp", "sub/drop.bin", "sub/nested/deep.txt"):
            self.assertNotIn(name, included)

    def test_directory_only_patterns_and_pruning(self) -> None:
        self.write(".gitignore", "cache/\nblocked/\n!blocked/keep.txt\n")
        self.write("cache/deep/file.txt")
        self.write("sub/cache")  # The same basename as a regular file is kept.
        self.write("blocked/keep.txt")
        self.write("blocked/.gitignore", "!keep.txt\n")
        included = self.collected()
        self.assertIn("sub/cache", included)
        self.assertNotIn("cache", included)
        self.assertNotIn("blocked", included)
        self.assertNotIn("blocked/keep.txt", included)

    def test_double_star_negation_escaping_and_case(self) -> None:
        self.write(
            ".gitignore",
            "# comment\n.env.*\n!.env.example\nlogs/**/drop[0-9].txt\n"
            "**/artifact?.bin\n\\#literal\n\\!literal\nspace\\ \ntrailing   \nCase.txt\n",
        )
        kept = (".env.example", "logs/deep/keep.txt", "case.txt", "space", "trailing space")
        dropped = (
            ".env.local", "logs/drop1.txt", "logs/a/b/drop2.txt", "artifact1.bin",
            "sub/artifact2.bin", "#literal", "!literal", "trailing", "Case.txt",
        )
        if os.name != "nt":
            dropped += ("space ",)
        for name in kept + dropped:
            self.write(name)
        included = self.collected()
        for name in kept:
            self.assertIn(name, included)
        for name in dropped:
            self.assertNotIn(name, included)

    def test_tracked_files_are_ignored_without_changing_source_metadata(self) -> None:
        self.write(".gitignore", "*.tmp\n.git/\n")
        self.write("tracked.tmp")
        self.write("untracked.tmp")
        self.write("keep.txt")
        self.git("init", "--quiet", "--template=")
        self.git("add", "--force", "tracked.tmp")
        index = (self.source / ".git/index").read_bytes()
        config = (self.source / ".git/config").read_bytes()
        included = self.collected()
        self.assertNotIn("tracked.tmp", included)
        self.assertNotIn("untracked.tmp", included)
        self.assertIn("keep.txt", included)
        self.assertEqual(index, (self.source / ".git/index").read_bytes())
        self.assertEqual(config, (self.source / ".git/config").read_bytes())
        bypassed = self.collected(use_ignore=False, exclude_patterns=(".git",))
        self.assertIn("tracked.tmp", bypassed)
        self.assertIn("untracked.tmp", bypassed)

    def test_only_source_gitignore_files_apply(self) -> None:
        self.write(".tarignore", "keep.txt\n")
        self.write("keep.txt")
        self.write("global.txt")
        self.write("info.txt")
        self.write("parent.txt")
        self.write(".gitignore", "Case.txt\n.git/\n")
        self.write("case.txt")
        self.git("init", "--quiet", "--template=")
        (self.source / ".git/info").mkdir(exist_ok=True)
        (self.source / ".git/info/exclude").write_text("info.txt\n", encoding="utf-8")
        global_ignore = self.root / "global-ignore"
        global_ignore.write_text("global.txt\n", encoding="utf-8")
        self.git("config", "core.excludesFile", str(global_ignore))
        (self.root / ".gitignore").write_text("parent.txt\n", encoding="utf-8")
        config = self.root / "gitconfig"
        config.write_text(f'[core]\nexcludesFile = {global_ignore.as_posix()}\nignoreCase = true\n', encoding="utf-8")
        with mock.patch.dict(os.environ, {
            "GIT_CONFIG_GLOBAL": str(config), "GIT_DIR": str(self.root / "missing"),
            "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.excludesFile",
            "GIT_CONFIG_VALUE_0": str(global_ignore),
        }):
            included = self.collected()
        for name in ("keep.txt", "global.txt", "info.txt", "parent.txt", "case.txt"):
            self.assertIn(name, included)

    def test_no_ignore_bypasses_git_and_preserves_explicit_excludes(self) -> None:
        self.write(".gitignore", "*.tmp\n")
        self.write("data.tmp")
        self.write("drop.log")
        with mock.patch.object(archive_core.subprocess, "run", side_effect=AssertionError("Git invoked")):
            included = self.collected(use_ignore=False, exclude_patterns=("*.log",))
            self.assertEqual(archive_core.collect_source_paths(self.source / "data.tmp"), [self.source / "data.tmp"])
        self.assertIn("data.tmp", included)
        self.assertNotIn("drop.log", included)

    def test_nul_delimited_unicode_and_unusual_names(self) -> None:
        self.write(".gitignore", "*.tmp\n")
        names = ("space name.txt", "caf\u00e9.txt", "-option.txt")
        if os.name != "nt":
            names += ("line\nbreak.txt",)
        for name in names:
            self.write(name)
        self.write("space name.tmp")
        included = self.collected()
        for name in names:
            self.assertIn(name, included)
        self.assertNotIn("space name.tmp", included)

    def test_git_failures_remove_temporary_metadata_and_leave_no_list(self) -> None:
        self.write(".gitignore", "*.tmp\n")
        original_run = subprocess.run
        for mode in ("missing", "init", "matching", "warning"):
            created = []

            def run(command, **options):
                if "init" in command:
                    created.append(pathlib.Path(command[-1]))
                    if mode == "missing":
                        raise FileNotFoundError("git missing")
                    if mode == "init":
                        return subprocess.CompletedProcess(command, 128, b"", b"init failure")
                    return original_run(command, **options)
                status = 1 if mode == "warning" else 128
                return subprocess.CompletedProcess(command, status, b"", b"matching failure")

            output = self.root / "entries.list"
            with self.subTest(mode=mode), mock.patch.object(archive_core.subprocess, "run", side_effect=run):
                with self.assertRaises(ValueError):
                    archive_core.list_source(self.source, output=output)
            self.assertFalse(output.exists())
            self.assertTrue(created)
            self.assertTrue(all(not path.exists() for path in created))

    def test_success_removes_temporary_metadata(self) -> None:
        with archive_core.gitignore_context(self.source) as (command, _):
            metadata = pathlib.Path(next(arg.split("=", 1)[1] for arg in command if arg.startswith("--git-dir=")))
            self.assertTrue(metadata.is_dir())
        self.assertFalse(metadata.exists())

    @unittest.skipIf(os.name == "nt", "symbolic links require Windows privileges")
    def test_symbolic_gitignore_is_rejected_without_following_it(self) -> None:
        target = self.root / "outside-ignore"
        target.write_text("data.txt\n", encoding="utf-8")
        (self.source / ".gitignore").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "symbolic .gitignore"):
            self.collected()

    def test_exclude_patterns_follow_tar_semantics(self) -> None:
        self.assertTrue(archive_core.is_excluded("node_modules", ("node_modules",)))
        self.assertTrue(archive_core.is_excluded("sub/node_modules", ("node_modules",)))
        self.assertTrue(archive_core.is_excluded("a.log", ("*.log",)))
        self.assertTrue(archive_core.is_excluded("sub/a.log", ("*.log",)))
        self.assertTrue(archive_core.is_excluded("logs/one.log", ("logs/*.log",)))
        self.assertFalse(archive_core.is_excluded("sub/logs/one.log", ("logs/*.log",)))
        self.assertFalse(archive_core.is_excluded("keep.txt", ("node_modules",)))

    def test_unreadable_gitignore_fails_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = pathlib.Path(temporary_directory)
            (source / ".gitignore").write_text("*.secret\n", encoding="utf-8")
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
