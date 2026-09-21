#!/usr/bin/env python3

"""Validate paths and portable tar structures for CustomShell archives."""

from __future__ import annotations

import datetime
import fnmatch
import os
import pathlib
import posixpath
import re
import sys
import tarfile


WINDOWS_DRIVE_PREFIX = re.compile(r"^[A-Za-z]:")
WINDOWS_FORBIDDEN_CHARACTERS = frozenset('<>:"\\|?*')
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
        or any(
            ord(character) < 32 or character in WINDOWS_FORBIDDEN_CHARACTERS
            for character in name
        )
        or name.endswith((" ", "."))
        or name.split(".", 1)[0].upper() in WINDOWS_RESERVED_NAMES
    ):
        raise ValueError(f"archive name is not portable to Windows: {name!r}")


def is_tarignored(
    rel_path: str, ignore_rules: list[tuple[str, str]]
) -> bool:
    for base_dir, pattern in ignore_rules:
        if base_dir:
            if not (rel_path == base_dir or rel_path.startswith(base_dir + "/")):
                continue
            in_scope = rel_path[len(base_dir) + 1:] if rel_path != base_dir else ""
        else:
            in_scope = rel_path

        if not pattern:
            continue
        if "/" not in pattern:
            name = pathlib.PurePosixPath(rel_path).name
            if fnmatch.fnmatch(name, pattern):
                return True
        else:
            pat = pattern.lstrip("/")
            if fnmatch.fnmatch(in_scope, pat) or fnmatch.fnmatch(in_scope, pat + "/*"):
                return True
    return False


def is_excluded(rel_path: str, patterns: tuple[str, ...]) -> bool:
    """Return True when rel_path matches a user --exclude pattern.

    Mirrors GNU tar's --exclude: a pattern without "/" matches the basename at
    any depth, while a pattern containing "/" is anchored to the source root and
    also covers the matching subtree.
    """
    name = pathlib.PurePosixPath(rel_path).name
    for pattern in patterns:
        if not pattern:
            continue
        if "/" not in pattern:
            if fnmatch.fnmatch(name, pattern):
                return True
        elif fnmatch.fnmatch(rel_path, pattern) or fnmatch.fnmatch(
            rel_path, pattern.rstrip("/") + "/*"
        ):
            return True
    return False


def read_tarignore(path: pathlib.Path, base_dir: str) -> list[tuple[str, str]]:
    rules = []
    with path.open("r", encoding="utf-8", errors="replace") as tarignore_file:
        for line in tarignore_file:
            pattern = line.strip()
            if pattern and not pattern.startswith("#"):
                rules.append((base_dir, pattern))
    return rules


def collect_source_paths(
    source_path: pathlib.Path,
    use_ignore: bool = True,
    exclude_patterns: tuple[str, ...] = (),
) -> list[pathlib.Path]:
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
                ignore_rules.extend(read_tarignore(tarignore_file, rel_dir))

        # Filter directories in-place to avoid descending into ignored dirs
        surviving_dirs = []
        for directory in dirs:
            dir_rel = f"{rel_dir}/{directory}" if rel_dir else directory
            if is_excluded(dir_rel, exclude_patterns):
                continue
            if use_ignore and is_tarignored(dir_rel, ignore_rules):
                continue
            surviving_dirs.append(directory)
            collected.append(current_dir / directory)
        dirs[:] = surviving_dirs

        for filename in files:
            file_rel = f"{rel_dir}/{filename}" if rel_dir else filename
            if is_excluded(file_rel, exclude_patterns):
                continue
            if use_ignore and is_tarignored(file_rel, ignore_rules):
                continue
            collected.append(current_dir / filename)

    return collected


def list_source(
    source_path: pathlib.Path,
    use_ignore: bool = True,
    exclude_patterns: tuple[str, ...] = (),
    output: pathlib.Path | None = None,
) -> int:
    """Validate the source tree and emit its archive entries as NUL records.

    Each record is the path relative to the source parent, prefixed with "./",
    which is exactly the list tar consumes with --files-from. Validation runs
    over the same filtered set that will be archived, so nothing is checked that
    is not stored and nothing is stored that is not checked.

    Records are written to ``output`` when given, otherwise to standard output.
    With ``output`` the entry count is printed to standard output so callers can
    drive progress without re-reading the list.
    """
    parent = source_path.parent
    paths = collect_source_paths(source_path, use_ignore, exclude_patterns)

    seen: dict[str, str] = {}
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

    stream = sys.stdout.buffer if output is None else open(output, "wb")
    try:
        for path in paths:
            relative = path.relative_to(parent).as_posix()
            stream.write(b"./" + relative.encode("utf-8", "surrogateescape") + b"\0")
        stream.flush()
    finally:
        if output is not None:
            stream.close()

    if output is not None:
        print(len(paths))
    return 0


def is_within(path: pathlib.Path, parent: pathlib.Path) -> bool:
    """Return True when path is parent itself or lies beneath it."""
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_destination(destination: str, home: str, repository: str) -> int:
    """Validate and canonicalize an extraction destination.

    Applies the same rules on both platforms: the destination must not be empty,
    must not be a symbolic link, must not be a filesystem root or the home or
    repository directory, must not be an existing non-directory, and its parent
    directory must already exist. The canonical destination is printed so the
    caller publishes to the resolved path.
    """
    if not destination:
        raise ValueError("destination is empty")
    requested = pathlib.Path(destination)
    if requested.is_symlink():
        raise ValueError(f"destination is a symbolic link: {requested}")
    resolved = pathlib.Path(os.path.realpath(str(requested)))
    if resolved == pathlib.Path(resolved.anchor):
        raise ValueError(f"refusing protected destination: {resolved}")
    protected = {
        pathlib.Path(os.path.realpath(home)),
        pathlib.Path(os.path.realpath(repository)),
    }
    if resolved in protected:
        raise ValueError(f"refusing protected destination: {resolved}")
    if resolved.exists() and not resolved.is_dir():
        raise ValueError(f"destination is not a directory: {resolved}")
    parent = resolved.parent
    if not parent.is_dir():
        raise ValueError(f"destination parent directory does not exist: {parent}")
    print(resolved)
    return 0


def resolve_output(source: str, output_base: str | None = None) -> int:
    """Validate and canonicalize the encrypted output path for Protect-Tar.

    ``source`` is the already-resolved absolute source path. The output is
    ``<output_base>_YYYYMMDD_HHMMSS.enc`` (defaulting to the source path) and
    must not already exist, must have an existing parent directory, and must not
    be created inside a directory source. The canonical output path is printed.
    """
    src = pathlib.Path(source)
    if src == pathlib.Path(src.anchor):
        raise ValueError(f"refusing filesystem root as source: {src}")
    base = pathlib.Path(output_base) if output_base else src
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = pathlib.Path(os.path.realpath(f"{base}_{timestamp}.enc"))
    out_dir = out.parent
    out_name = out.name
    if not out_dir.is_dir():
        raise ValueError(f"output parent directory does not exist: {out_dir}")
    out_dir = pathlib.Path(os.path.realpath(str(out_dir)))
    out = out_dir / out_name
    if out.exists() or out.is_symlink():
        raise ValueError(f"output already exists: {out}")
    if src.is_dir():
        canonical = pathlib.Path(os.path.realpath(str(out)))
        if is_within(canonical, src):
            raise ValueError("output cannot be created inside the source directory")
    print(out)
    return 0


def normalized_member_path(name: str) -> str:
    normalized = name.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    if (
        not normalized
        or normalized.startswith("/")
        or WINDOWS_DRIVE_PREFIX.match(normalized)
    ):
        raise ValueError(f"unsafe archive path: {name!r}")
    parts = pathlib.PurePosixPath(normalized).parts
    if ".." in parts:
        raise ValueError(f"unsafe archive path: {name!r}")
    return "/".join(part for part in parts if part not in {"", "."})


def validate_member_type(
    member: tarfile.TarInfo, normalized: str, platform: str
) -> None:
    if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
        raise ValueError(f"unsupported archive member type: {normalized!r}")
    if platform == "windows" and (member.issym() or member.islnk()):
        raise ValueError(f"archive links are not supported on Windows: {normalized!r}")


def validate_link_target(
    member: tarfile.TarInfo, normalized: str, top_level: str
) -> None:
    target = member.linkname.replace("\\", "/")
    if target.startswith("/") or WINDOWS_DRIVE_PREFIX.match(target):
        raise ValueError(f"archive link target escapes extraction: {target!r}")
    base = posixpath.dirname(normalized) if member.issym() else ""
    resolved = posixpath.normpath(posixpath.join(base, target))
    if (
        resolved == ".."
        or resolved.startswith("../")
        or resolved.split("/", 1)[0] != top_level
    ):
        raise ValueError(f"archive link target escapes extraction: {target!r}")


def has_symlink_ancestor(path: str, symlinks: set[str]) -> bool:
    ancestors = path.split("/")[:-1]
    return any(
        "/".join(ancestors[:depth]) in symlinks
        for depth in range(1, len(ancestors) + 1)
    )


def validate_tar(tar_path: pathlib.Path, platform: str) -> int:
    seen: dict[str, str] = {}
    members: list[tuple[tarfile.TarInfo, str]] = []
    top_levels: set[str] = set()
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
            validate_member_type(member, normalized, platform)
            members.append((member, normalized))

    if len(top_levels) != 1:
        raise ValueError("archive must contain exactly one top-level item")

    symlinks = {name for member, name in members if member.issym()}
    top_level = next(iter(top_levels))
    for member, normalized in members:
        if has_symlink_ancestor(normalized, symlinks):
            raise ValueError(
                f"archive member traverses a symbolic link: {normalized!r}"
            )
        if member.issym() or member.islnk():
            validate_link_target(member, normalized, top_level)
    print(len(members))
    return 0


def main() -> int:
    if sys.version_info < (3, 8):
        print(
            "archive_core.py requires Python 3.8 or newer "
            f"(found {sys.version.split()[0]}).",
            file=sys.stderr,
        )
        return 69
    if len(sys.argv) < 3:
        print("usage: archive_core.py <operation> <arguments...>", file=sys.stderr)
        return 64
    operation = sys.argv[1]
    try:
        if operation == "list-source":
            source = pathlib.Path(sys.argv[2])
            use_ignore = True
            excludes: list[str] = []
            output: pathlib.Path | None = None
            index = 3
            while index < len(sys.argv):
                argument = sys.argv[index]
                if argument == "--no-ignore":
                    use_ignore = False
                    index += 1
                elif argument == "--exclude":
                    if index + 1 >= len(sys.argv) or not sys.argv[index + 1]:
                        return 64
                    excludes.append(sys.argv[index + 1])
                    index += 2
                elif argument == "--output":
                    if index + 1 >= len(sys.argv) or not sys.argv[index + 1]:
                        return 64
                    output = pathlib.Path(sys.argv[index + 1])
                    index += 2
                else:
                    return 64
            return list_source(source, use_ignore, tuple(excludes), output)
        if operation == "validate-destination":
            if len(sys.argv) < 3:
                return 64
            destination = sys.argv[2]
            home: str | None = None
            repository: str | None = None
            index = 3
            while index < len(sys.argv):
                argument = sys.argv[index]
                if argument == "--home":
                    if index + 1 >= len(sys.argv):
                        return 64
                    home = sys.argv[index + 1]
                    index += 2
                elif argument == "--repository":
                    if index + 1 >= len(sys.argv):
                        return 64
                    repository = sys.argv[index + 1]
                    index += 2
                else:
                    return 64
            if home is None or repository is None:
                return 64
            return validate_destination(destination, home, repository)
        if operation == "resolve-output":
            if len(sys.argv) not in (3, 4):
                return 64
            return resolve_output(
                sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else None
            )
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
