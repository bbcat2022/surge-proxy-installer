#!/usr/bin/env python3
"""Reject files and content that must not enter the public repository."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


BLOCKED_PATHS = (
    re.compile(r"^[0-9]{2}\. .*\.md$"),
    re.compile(r"(^|/)(?:config\.ya?ml|\.env(?:\..*)?|.*\.(?:pem|key|p12|pfx))$", re.I),
    re.compile(r"(^|/)(?:secrets?|private)(?:/|$)", re.I),
    re.compile(r"^proxy-installer/dist/"),
    re.compile(r"^\.private-upload-denylist$"),
)
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"),
    re.compile(r"\b(?:ghp|gho)_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
)


def git_paths(root: Path, mode: str) -> list[str]:
    command = ["git", "-C", str(root), "ls-files"] if mode == "tracked" else ["git", "-C", str(root), "diff", "--cached", "--name-only", "--diff-filter=ACMR"]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("unable to enumerate Git paths")
    return [line for line in result.stdout.splitlines() if line]


def denylist(root: Path) -> list[str]:
    path = root / ".private-upload-denylist"
    if not path.is_file():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip() and not line.lstrip().startswith("#")]


def inspect(root: Path, paths: list[str], forbidden: list[str]) -> list[str]:
    failures: list[str] = []
    for relative in paths:
        if any(pattern.search(relative) for pattern in BLOCKED_PATHS):
            failures.append(f"blocked path: {relative}")
            continue
        path = root / relative
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8", errors="ignore")
        if any(pattern.search(content) for pattern in SECRET_PATTERNS):
            failures.append(f"possible credential: {relative}")
        if any(value in relative or value in content for value in forbidden):
            failures.append(f"matches local private denylist: {relative}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--mode", choices=("tracked", "staged"), default="staged")
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        failures = inspect(root, git_paths(root, args.mode), denylist(root))
    except (OSError, RuntimeError) as exc:
        print(f"publication-guard=failed: {exc}", file=sys.stderr)
        return 2
    if failures:
        print("publication-guard=failed", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"publication-guard=success mode={args.mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
