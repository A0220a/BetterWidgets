#!/usr/bin/env python3
"""Inspect the Git index without printing matched credential values.

This is a publication hygiene check, not an exhaustive secret scanner.
"""

import pathlib
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args])


def main():
    root = git("rev-parse", "--show-toplevel").decode().strip()
    paths = git("-C", root, "ls-files", "-z").decode().split("\0")
    forbidden_parts = {"xcuserdata", "dist", "build", "DerivedData", ".build", "private-media"}
    forbidden_suffixes = {
        ".xcuserstate", ".p12", ".pfx", ".p8", ".pem", ".key", ".cer",
        ".mobileprovision", ".provisionprofile", ".keychain", ".keychain-db",
        ".log", ".dmg", ".zip", ".pyc",
    }
    patterns = {
        "private key": re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----"),
        "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
        "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
        "OpenAI API key": re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b"),
        "local home path": re.compile(r"/(?:Users|home)/[^/\s]+/"),
        "email address": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
        "embedded URL credentials": re.compile(r"https?://[^\s/:]+:[^\s/@]+@"),
        "developer team": re.compile(r'DEVELOPMENT_TEAM\s*=\s*"?[A-Z0-9]{10}"?\s*;'),
    }
    failures = []
    count = 0
    for name in filter(None, paths):
        path = pathlib.PurePosixPath(name)
        if (forbidden_parts.intersection(path.parts)
                or path.suffix.lower() in forbidden_suffixes
                or path.name in {".DS_Store", "widgets.json", ".env"}
                or (path.name.startswith(".env.") and path.name != ".env.example")):
            failures.append(f"{name}: local/private/generated file is tracked")
            continue
        blob = subprocess.check_output(["git", "-C", root, "show", f":{name}"])
        count += 1
        if b"\0" in blob:
            continue
        text = blob.decode("utf-8", errors="replace")
        for label, pattern in patterns.items():
            if pattern.search(text):
                failures.append(f"{name}: review {label} (value redacted)")
    if failures:
        print("Repository hygiene FAILED:\n" + "\n".join(failures), file=sys.stderr)
        return 1
    print(f"PASS: {count} staged files; no forbidden paths or checked credential patterns")
    return 0


if __name__ == "__main__":
    sys.exit(main())
