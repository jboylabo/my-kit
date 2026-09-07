#!/usr/bin/env python3
"""Parse and update the Spec Kit issues draft file (default: issues/issues.md).

Subcommands
-----------
parse  <file>                 Emit the parsed entries as JSON.
update <file> --set ID=NUM    Write issue numbers back into the file and
                              regenerate the summary table. Human edits to
                              titles / bodies are preserved: only the
                              ``**issue**:`` lines and the summary block change.

File format
-----------
    ---
    feature: 001-example
    source: specs/001-example/tasks.md
    repo: owner/name
    ---

    # Issues - 001-example

    <!-- speckit:summary -->
    | Task | Issue | Title |
    | --- | --- | --- |
    <!-- speckit:summary-end -->

    <!-- speckit:issue id=T001 -->
    ## T001 - Create project structure

    **labels**: setup, P1
    **milestone**: 001-example
    **assignees**:
    **issue**:

    Body markdown continues until the next `speckit:issue` marker or EOF.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

MARKER_RE = re.compile(
    r"^<!--\s*speckit:issue\s+id=([A-Za-z][A-Za-z0-9_.-]*)\s*-->[ \t]*$", re.M
)
HEADING_RE = re.compile(r"^##\s+(.*?)\s*$")
META_RE = re.compile(r"^\*\*(labels|milestone|assignees|issue|title)\*\*\s*:\s*(.*?)\s*$", re.I)
SUMMARY_BEGIN = "<!-- speckit:summary -->"
SUMMARY_END = "<!-- speckit:summary-end -->"
EMPTY_TOKENS = {"", "-", "—", "–", "none", "n/a", "tbd"}


def _is_empty(value: str) -> bool:
    return value.strip().lower() in EMPTY_TOKENS


def _split_list(value: str) -> list[str]:
    if _is_empty(value):
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def _strip_id_prefix(task_id: str, title: str) -> str:
    """Turn 'T001 - Create structure' or 'T001: Create structure' into the bare title."""
    pattern = re.compile(
        r"^\[?" + re.escape(task_id) + r"\]?\s*[:\-—–]?\s*", re.I
    )
    return pattern.sub("", title).strip() or title.strip()


def read_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    meta: dict[str, str] = {}
    for line in text[3:end].splitlines():
        if ":" in line and not line.strip().startswith("#"):
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    return meta


def parse(text: str) -> list[dict]:
    entries: list[dict] = []
    marks = list(MARKER_RE.finditer(text))
    for index, mark in enumerate(marks):
        task_id = mark.group(1)
        start = mark.end()
        end = marks[index + 1].start() if index + 1 < len(marks) else len(text)
        block = text[start:end]

        title = ""
        meta: dict[str, str] = {}
        body_lines: list[str] = []
        seen_heading = False
        in_meta = True

        for line in block.splitlines():
            if not seen_heading:
                if not line.strip():
                    continue
                heading = HEADING_RE.match(line)
                if heading:
                    title = _strip_id_prefix(task_id, heading.group(1))
                    seen_heading = True
                    continue
                # No heading: fall through and treat the block as metadata + body.
                seen_heading = True

            if in_meta:
                if not line.strip():
                    continue
                found = META_RE.match(line)
                if found:
                    meta[found.group(1).lower()] = found.group(2)
                    continue
                in_meta = False

            body_lines.append(line)

        if meta.get("title") and not _is_empty(meta["title"]):
            title = _strip_id_prefix(task_id, meta["title"])

        raw = meta.get("issue", "")
        issue_ref = "" if _is_empty(raw) else raw.strip()
        issue_number = None
        if issue_ref and re.fullmatch(r"#?\d+", issue_ref):
            issue_number = int(issue_ref.lstrip("#"))

        milestone = meta.get("milestone", "")
        entries.append(
            {
                "id": task_id,
                "title": title,
                "labels": _split_list(meta.get("labels", "")),
                "assignees": _split_list(meta.get("assignees", "")),
                "milestone": "" if _is_empty(milestone) else milestone.strip(),
                "issue": issue_number,
                "issue_ref": issue_ref,
                "body": "\n".join(body_lines).strip(),
            }
        )
    return entries


def render_summary(entries: list[dict]) -> str:
    rows = ["| Task | Issue | Title |", "| --- | --- | --- |"]
    for entry in entries:
        issue = entry["issue_ref"] or "—"
        title = entry["title"].replace("|", "\\|")
        rows.append(f"| {entry['id']} | {issue} | {title} |")
    return "\n".join(rows)


def format_ref(value: str) -> str:
    """GitHub numbers render as #12; tracker keys (ABC-123) pass through as-is."""
    value = value.strip().lstrip("#")
    return f"#{value}" if value.isdigit() else value


def apply_updates(text: str, updates: dict[str, str]) -> str:
    """Write issue numbers into the matching blocks without touching anything else."""
    marks = list(MARKER_RE.finditer(text))
    # Rewrite from the bottom so earlier offsets stay valid.
    for index in range(len(marks) - 1, -1, -1):
        mark = marks[index]
        task_id = mark.group(1)
        if task_id not in updates:
            continue
        start = mark.end()
        end = marks[index + 1].start() if index + 1 < len(marks) else len(text)
        block = text[start:end]
        ref = format_ref(updates[task_id])

        replaced = re.subn(
            r"^\*\*issue\*\*\s*:.*$",
            f"**issue**: {ref}",
            block,
            count=1,
            flags=re.M | re.I,
        )
        if replaced[1]:
            block = replaced[0]
        else:
            # No **issue** line yet: insert one after the last metadata line.
            lines = block.splitlines()
            insert_at = 0
            for position, line in enumerate(lines):
                if META_RE.match(line) or HEADING_RE.match(line):
                    insert_at = position + 1
            lines.insert(insert_at, f"**issue**: {ref}")
            block = "\n".join(lines)
        text = text[:start] + block + text[end:]

    entries = parse(text)
    summary = render_summary(entries)
    begin = text.find(SUMMARY_BEGIN)
    finish = text.find(SUMMARY_END)
    if begin != -1 and finish != -1 and finish > begin:
        text = (
            text[: begin + len(SUMMARY_BEGIN)]
            + "\n"
            + summary
            + "\n"
            + text[finish:]
        )
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    parse_cmd = sub.add_parser("parse", help="print parsed entries as JSON")
    parse_cmd.add_argument("file")
    parse_cmd.add_argument("--pending", action="store_true", help="only entries without an issue number")

    update_cmd = sub.add_parser("update", help="write issue numbers back into the file")
    update_cmd.add_argument("file")
    update_cmd.add_argument("--set", action="append", default=[], metavar="ID=REF")

    export_cmd = sub.add_parser(
        "export", help="write one file per field into a directory (safe for shell loops)"
    )
    export_cmd.add_argument("file")
    export_cmd.add_argument("--out-dir", required=True)
    export_cmd.add_argument("--pending", action="store_true")

    args = parser.parse_args()
    path = Path(args.file)
    if not path.is_file():
        print(f"Error: {path} not found", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")

    if args.command == "parse":
        entries = parse(text)
        if args.pending:
            entries = [entry for entry in entries if not entry["issue_ref"]]
        json.dump(
            {"frontmatter": read_frontmatter(text), "entries": entries},
            sys.stdout,
            ensure_ascii=False,
        )
        sys.stdout.write("\n")
        return 0

    if args.command == "export":
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        entries = parse(text)
        if args.pending:
            entries = [entry for entry in entries if not entry["issue_ref"]]
        for entry in entries:
            stem = out_dir / entry["id"]
            stem.with_suffix(".title").write_text(entry["title"], encoding="utf-8")
            stem.with_suffix(".body").write_text(entry["body"], encoding="utf-8")
            stem.with_suffix(".labels").write_text(
                "\n".join(entry["labels"]), encoding="utf-8"
            )
            stem.with_suffix(".assignees").write_text(
                "\n".join(entry["assignees"]), encoding="utf-8"
            )
            stem.with_suffix(".milestone").write_text(entry["milestone"], encoding="utf-8")
            print(entry["id"])
        return 0

    updates: dict[str, str] = {}
    for pair in args.set:
        key, sep, value = pair.partition("=")
        value = value.strip()
        if not key.strip() or not sep or not value or any(c.isspace() for c in value):
            print(f"Error: --set expects ID=REF (e.g. T001=12 or T001=ABC-123), got '{pair}'",
                  file=sys.stderr)
            return 1
        updates[key.strip()] = value

    path.write_text(apply_updates(text, updates), encoding="utf-8")
    print(f"Updated {len(updates)} entries in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
