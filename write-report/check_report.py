#!/usr/bin/env python3
"""
Check Markdown reports against the write-report conventions.

Usage: python3 check_report.py FILE [FILE ...]

Prints one line per problem as ``FILE:LINE: message`` and exits with status 1,
or prints ``OK`` and exits with status 0 when every file passes.
"""

import argparse
import datetime
import re
import sys
from pathlib import Path
from urllib.parse import unquote

CLAUDE_AUTHOR = "CLAUDE (C)"
AUTHOR_TAG = re.compile(r"\((?:H|C|H\+C)\)$")
ISO_DATE = re.compile(r"\d{4}-\d{2}-\d{2}$")
KEY_LINE = re.compile(r"([A-Za-z_][\w-]*):\s*(.*)$")
FENCE = re.compile(r"(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+).*?\1")
LINK = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
WIKILINK = re.compile(r"\[\[[^\]]+\]\]")
SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*:")


### ---------------------------------------------------------------------------
### Frontmatter
### ---------------------------------------------------------------------------

def read_frontmatter(lines):
    """
    Parse the top-level keys of the YAML frontmatter.

    Parameters
    ----------
    lines : list of str
        Lines of the file, without line endings.

    Returns
    -------
    fields : dict of str to str or None
        Value of each top-level key, with continuation lines (such as YAML
        list items) joined by spaces. None if the file does not start with a
        frontmatter block closed by ``---``.
    body_start : int
        Index of the first line after the frontmatter, 0 if there is none.
    """
    if not lines or lines[0].strip() != "---":
        return None, 0
    fields = {}
    key = None
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return fields, index + 1
        match = KEY_LINE.match(line)
        if match:
            key = match.group(1)
            fields[key] = match.group(2).strip()
        elif key is not None and line.strip():
            item = line.strip().lstrip("-").strip()
            fields[key] = f"{fields[key]} {item}".strip()
    return None, 0


def check_frontmatter(fields, today):
    """
    Check the frontmatter keys, dates and authors.

    Parameters
    ----------
    fields : dict of str to str
        Frontmatter keys and values, as returned by `read_frontmatter`.
    today : str
        Today's date as YYYY-MM-DD, the value `updated` must have.

    Returns
    -------
    problems : list of str
        One message per problem found.
    """
    problems = []
    has_created = "created" in fields or "date" in fields
    for key, present in (("title", "title" in fields),
                         ("created", has_created),
                         ("updated", "updated" in fields),
                         ("authors", "authors" in fields)):
        if not present:
            problems.append(f"frontmatter has no '{key}'")
    for key in ("created", "date", "updated"):
        if key not in fields:
            continue
        value = fields[key].strip("'\"")
        try:
            if not ISO_DATE.match(value):
                raise ValueError
            datetime.date.fromisoformat(value)
        except ValueError:
            problems.append(f"'{key}' is not a YYYY-MM-DD date: {value!r}")
            continue
        if key == "updated" and value != today:
            problems.append(f"'updated' is {value}, not today ({today})")
    if ("authors" in fields and CLAUDE_AUTHOR not in fields["authors"]
            and (fields.get("type") or "").strip() != "digest"):
        problems.append(f"'authors' does not list {CLAUDE_AUTHOR}")
    return problems


### ---------------------------------------------------------------------------
### Body
### ---------------------------------------------------------------------------

def check_body(lines, start, base_dir):
    """
    Check H2 author tags and links outside fenced code blocks.

    Parameters
    ----------
    lines : list of str
        Lines of the file, without line endings.
    start : int
        Index of the first body line (after the frontmatter).
    base_dir : pathlib.Path
        Directory that relative links resolve against.

    Returns
    -------
    problems : list of tuple of (int, str)
        Line number (1-based) and message for each problem found.
    """
    problems = []
    fence = None
    for number, line in enumerate(lines[start:], start=start + 1):
        stripped = line.lstrip()
        if fence is not None:
            closing = re.match(rf"{re.escape(fence[0])}{{{len(fence)},}}\s*$",
                               stripped)
            if closing:
                fence = None
            continue
        opening = FENCE.match(stripped)
        if opening:
            fence = opening.group(1)
            continue
        if line.startswith("## ") and not AUTHOR_TAG.search(line.strip()):
            problems.append((number, "H2 has no author tag such as (H), (C) "
                                     f"or (H+C): {line.strip()!r}"))
        text = INLINE_CODE.sub("", line)
        if WIKILINK.search(text):
            problems.append((number, "wikilink; use a relative markdown link"))
        for target in LINK.findall(text):
            if target.startswith("#") or SCHEME.match(target):
                continue
            path = unquote(target.split("#", 1)[0])
            if path and not (base_dir / Path(path).expanduser()).exists():
                problems.append((number, f"link target not found: {target}"))
    return problems


### ---------------------------------------------------------------------------
### Entry point
### ---------------------------------------------------------------------------

def check_file(path, today):
    """
    Run every check on one report.

    Parameters
    ----------
    path : pathlib.Path
        Report to check.
    today : str
        Today's date as YYYY-MM-DD.

    Returns
    -------
    problems : list of tuple of (int, str)
        Line number (1-based, 1 for frontmatter problems) and message for
        each problem found.
    """
    if not path.is_file():
        return [(0, "file not found")]
    lines = path.read_text(encoding="utf-8").splitlines()
    fields, body_start = read_frontmatter(lines)
    if fields is None:
        problems = [(1, "no frontmatter block (opened and closed by '---')")]
    else:
        problems = [(1, msg) for msg in check_frontmatter(fields, today)]
    problems += check_body(lines, body_start, path.parent)
    return problems


def main(argv=None):
    """
    Check the files given on the command line and report the problems.

    Parameters
    ----------
    argv : list of str, optional
        Command-line arguments without the program name. Default is None,
        which reads `sys.argv`.

    Returns
    -------
    status : int
        0 if every file passes, 1 otherwise.
    """
    parser = argparse.ArgumentParser(
        description="Check Markdown reports against write-report.")
    parser.add_argument("files", nargs="+", type=Path, help="reports to check")
    args = parser.parse_args(argv)
    today = datetime.date.today().isoformat()
    failed = False
    for path in args.files:
        for number, message in check_file(path, today):
            print(f"{path}:{number}: {message}")
            failed = True
    if not failed:
        print("OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
