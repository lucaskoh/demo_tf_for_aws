#!/usr/bin/env python3
"""Checks the links of README.md and docs/*.md: every relative file must exist and every #anchor must
match a heading of the file it points at. External links (http, https, mailto) are not followed.

Usage: scripts/check-docs.py          (no dependencies; exit code 1 when a link is broken)
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^\s*(```|~~~)")


def slug(heading: str) -> str:
    """GitHub's anchor for a heading: lowercase, punctuation removed, spaces become hyphens."""
    text = re.sub(r"`", "", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return text.replace(" ", "-")


def body_lines(path: Path):
    """Yield (line number, text) of the lines that are not inside a code fence."""
    in_fence = False
    for number, line in enumerate(path.read_text().split("\n"), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield number, line


def anchors(path: Path):
    seen, result = {}, set()
    for _, line in body_lines(path):
        match = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if match:
            base = slug(match.group(1))
            count = seen.get(base, 0)
            seen[base] = count + 1
            result.add(base if count == 0 else f"{base}-{count}")
    return result


def main():
    files = [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]
    files = [f for f in files if f.is_file()]
    cache = {}
    errors = []

    for path in files:
        for number, line in body_lines(path):
            for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
                if re.match(r"^(https?:|mailto:)", target):
                    continue
                file_part, _, anchor = target.partition("#")
                destination = path if not file_part else (path.parent / file_part).resolve()
                shown = path.relative_to(ROOT)
                if not destination.exists():
                    errors.append(f"{shown}:{number}: {target}: the file does not exist")
                    continue
                if anchor and destination.suffix == ".md":
                    cache.setdefault(destination, anchors(destination))
                    if anchor not in cache[destination]:
                        errors.append(f"{shown}:{number}: {target}: there is no heading '#{anchor}' in {destination.relative_to(ROOT)}")

    for error in errors:
        print(error)
    print(f"{len(files)} file(s) checked, {len(errors)} broken link(s).")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
