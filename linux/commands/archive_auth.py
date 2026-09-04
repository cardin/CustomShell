#!/usr/bin/env python3

"""Validate paths and portable tar structures for CustomShell archives."""

import fnmatch
import os
import pathlib
import posixpath
import re
import sys
import tarfile


WINDOWS_RESERVED_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{number}" for number in range(1, 10)),
    *(f"LPT{number}" for number in range(1, 10)),
}


def validate_windows_name(name: str) -> None:
    if (
        not name
        or any(ord(character) < 32 or character in '<>:"\\|?*' for character in name)
        or name.endswith((" ", "."))
        or name.split(".", 1)[0].upper() in WINDOWS_RESERVED_NAMES
    ):
        raise ValueError(f"archive name is not portable to Windows: {name!r}")


def is_tarignored(rel_path: str, is_dir: bool, ignore_rules: list[tuple[str, str]]) -> bool:
    for base_dir, pattern in ignore_rules:
        if base_dir:
            if not (rel_path == base_dir or rel_path.startswith(base_dir + "/")):
                continue
            in_scope = rel_path[len(base_dir) + 1:] if rel_path != base_dir else ""
        else:
            in_scope = rel_path

        clean_pattern = pattern.rstrip("/")
        if "/" not in clean_pattern:
            name = pathlib.PurePosixPath(rel_path).name
            if fnmatch.fnmatch(name, clean_pattern):
                return True
        else:
            pat = clean_pattern.lstrip("/")
            if fnmatch.fnmatch(in_scope, pat) or fnmatch.fnmatch(in_scope, pat + "/*"):
                return True
    return False


def collect_source_paths(source_path: pathlib.Path, use_ignore: bool = True) -> list[pathlib.Path]:
    if not source_path.is_dir() or source_path.is_symlink():
        return [source_path]

    collected = [source_path]
    ignore_rules: list[tuple[str, str]] = []

    for root, dirs, files in os.walk(source_path):
        current_dir = pathlib.Path(root)
        rel_dir = current_dir.relative_to(source_path).as_posix()
        if rel_dir == ".":
            rel_dir = ""

        if use_ignore:
            tarignore_file = current_dir / ".tarignore"
            if tarignore_file.is_file():
                try:
                    with tarignore_file.open("r", encoding="utf-8", errors="replace") as f:
                        for line in f:
                            line = line.strip()
                            if line and not line.startswith("#"):
                                ignore_rules.append((rel_dir, line))
                except OSError:
                    pass

        # Filter directories in-place to avoid descending into ignored dirs
        surviving_dirs = []
        for d in dirs:
            dir_rel = f"{rel_dir}/{d}" if rel_dir else d
            if not use_ignore or not is_tarignored(dir_rel, True, ignore_rules):
                surviving_dirs.append(d)
                collected.append(current_dir / d)
        dirs[:] = surviving_dirs

        for f in files:
            file_rel = f"{rel_dir}/{f}" if rel_dir else f
            if not use_ignore or not is_tarignored(file_rel, False, ignore_rules):
                collected.append(current_dir / f)

    return collected


def validate_source(source_path: pathlib.Path, use_ignore: bool = True) -> int:
    parent = source_path.parent
    seen = {}
    paths = collect_source_paths(source_path, use_ignore)
    for path in paths:
        relative = path.relative_to(parent).as_posix()
        for component in pathlib.PurePosixPath(relative).parts:
            validate_windows_name(component)
        folded = relative.casefold()
        if folded in seen and seen[folded] != relative:
            raise ValueError(
                f"archive paths collide on Windows: {seen[folded]!r} and {relative!r}"
            )
        seen[folded] = relative
    print(len(paths))
    return 0


def normalized_member_path(name: str) -> str:
    normalized = name.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    if not normalized or normalized.startswith("/") or re.match(r"^[A-Za-z]:", normalized):
        raise ValueError(f"unsafe archive path: {name!r}")
    parts = pathlib.PurePosixPath(normalized).parts
    if ".." in parts:
        raise ValueError(f"unsafe archive path: {name!r}")
    return "/".join(part for part in parts if part not in {"", "."})


def validate_tar(tar_path: pathlib.Path, platform: str) -> int:
    seen = {}
    members = []
    top_levels = set()
    with tarfile.open(tar_path, "r:gz") as archive:
        for member in archive.getmembers():
            normalized = normalized_member_path(member.name)
            if not normalized:
                continue
            components = normalized.split("/")
            for component in components:
                validate_windows_name(component)
            top_levels.add(components[0])
            folded = normalized.casefold()
            if folded in seen:
                raise ValueError(f"duplicate or colliding archive path: {normalized!r}")
            seen[folded] = normalized
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError(f"unsupported archive member type: {normalized!r}")
            if platform == "windows" and (member.issym() or member.islnk()):
                raise ValueError(f"archive links are not supported on Windows: {normalized!r}")
            members.append((member, normalized))

    if len(top_levels) != 1:
        raise ValueError("archive must contain exactly one top-level item")

    symlinks = {name for member, name in members if member.issym()}
    top_level = next(iter(top_levels))
    for member, normalized in members:
        ancestors = normalized.split("/")[:-1]
        for depth in range(1, len(ancestors) + 1):
            if "/".join(ancestors[:depth]) in symlinks:
                raise ValueError(f"archive member traverses a symbolic link: {normalized!r}")
        if member.issym() or member.islnk():
            target = member.linkname.replace("\\", "/")
            if target.startswith("/") or re.match(r"^[A-Za-z]:", target):
                raise ValueError(f"archive link target escapes extraction: {target!r}")
            base = posixpath.dirname(normalized) if member.issym() else ""
            resolved = posixpath.normpath(posixpath.join(base, target))
            if resolved == ".." or resolved.startswith("../") or resolved.split("/", 1)[0] != top_level:
                raise ValueError(f"archive link target escapes extraction: {target!r}")
    print(len(members))
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: archive_auth.py <operation> <arguments...>", file=sys.stderr)
        return 64
    operation = sys.argv[1]
    try:
        if operation == "validate-source":
            if len(sys.argv) not in (3, 4):
                return 64
            use_ignore = True
            if len(sys.argv) == 4:
                if sys.argv[3] != "--no-ignore":
                    return 64
                use_ignore = False
            return validate_source(pathlib.Path(sys.argv[2]), use_ignore)
        if operation == "validate-tar":
            if len(sys.argv) != 4 or sys.argv[3] not in {"linux", "windows"}:
                return 64
            return validate_tar(pathlib.Path(sys.argv[2]), sys.argv[3])
        return 64
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f"archive validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
