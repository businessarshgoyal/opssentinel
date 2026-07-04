#!/usr/bin/env python3
"""Fail if any tracked text file contains an em dash or en dash.

The OpsSentinel style rule forbids em dashes anywhere in code, comments, SQL, or
documentation. This check enforces it and runs in CI so the rule cannot regress.
"""

import os
import sys

FORBIDDEN = ["\u2014", "\u2013"]  # em dash, en dash
TEXT_EXTENSIONS = {
    ".py", ".sql", ".md", ".sh", ".toml", ".json", ".yml", ".yaml", ".txt", ".cfg",
}
SKIP_DIRS = {".git", "generated", "__pycache__", ".pytest_cache", "node_modules"}


def is_text_file(path: str) -> bool:
    _, ext = os.path.splitext(path)
    return ext.lower() in TEXT_EXTENSIONS


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    offenders = []
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            path = os.path.join(current, name)
            if not is_text_file(path):
                continue
            with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                for lineno, line in enumerate(handle, start=1):
                    if any(ch in line for ch in FORBIDDEN):
                        rel = os.path.relpath(path, root)
                        offenders.append("%s:%d" % (rel, lineno))
    if offenders:
        print("Found forbidden dash characters in:")
        for item in offenders:
            print("  " + item)
        return 1
    print("No em dashes or en dashes found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
