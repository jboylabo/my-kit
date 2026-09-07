---
name: "speckit-issues"
description: "Turn the current feature's tasks.md into reviewable GitHub issue drafts, push them to GitHub, and create an issue-linked branch when you start a task."
argument-hint: "(empty) | push | status | branch <TASK_ID> | <TASK_ID>"
compatibility: "Requires spec-kit project structure with .specify/ directory, the gh CLI, python3, and a github.com origin remote"
metadata:
  author: "my-kit"
  source: ".specify/extensions/issues"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

Bridge Spec Kit's `tasks.md` to GitHub, in the order the team works:

```
/speckit-tasks  →  tasks.md
       ↓
/speckit-issues            draft   issues/issues.md を生成（GitHub には触らない）
       ↓ 人がレビュー・編集
/speckit-issues push       push    Issue を作成し、#番号を issues.md に書き戻す
       ↓
/speckit-issues T005       branch  その Issue に紐づくブランチを作って checkout
```

All GitHub mutations go through `.specify/extensions/issues/scripts/bash/issues.sh`,
which pins every `gh` call to the slug parsed from `git remote get-url origin`.

> [!CAUTION]
> NEVER create issues in a repository other than the one the `origin` remote points to.
> Do not call `gh issue create` directly — always go through `issues.sh push`, which enforces this.

## Mode Selection

Read `$ARGUMENTS` and pick exactly one mode:

| `$ARGUMENTS` | Mode |
|---|---|
| empty, or `draft` | **Draft** |
| starts with `push` | **Push** |
| starts with `status` | **Status** |
| starts with `branch`, or matches `^T\d+$` | **Branch** |
| anything else | Treat as extra guidance for **Draft** (e.g. "P1 のタスクだけ") |

---

## Mode: Draft

1. Run from the repo root and parse the output:

   ```bash
   bash .specify/extensions/issues/scripts/bash/issues.sh paths --json
   ```

   It yields `REPO_ROOT`, `FEATURE`, `FEATURE_DIR`, `TASKS`, `ISSUES_FILE`, `REPO_SLUG`.
   If `TASKS` does not exist, stop and tell the user to run `/speckit-tasks` first.
   If `REPO_SLUG` is `(unresolved)`, stop and report that the origin remote is missing or not GitHub.

2. Create the scaffold (this fills the frontmatter and the summary markers):

   ```bash
   bash .specify/extensions/issues/scripts/bash/issues.sh init
   ```

   If it reports that the file already exists and is not empty, do **not** pass `--force`
   on your own. Run **Status** instead, show the user what is already there, and ask
   whether to append new tasks or start over.

3. Read `TASKS` (`tasks.md`) and, **IF EXISTS**, `.specify/memory/constitution.md`,
   `FEATURE_DIR/spec.md` and `FEATURE_DIR/plan.md` for context.

4. Append one entry per task to `ISSUES_FILE`, below the `---` at the end of the scaffold.
   Task lines in `tasks.md` begin with a markdown checkbox, so strip the leading `- [ ]`
   and any `[P]` / `[US#]` markers to recover the task ID and description.

   Use exactly this shape, with the marker comment starting at column 1:

   ```
   <!-- speckit:issue id=T001 -->
   ## T001 — Create the project skeleton

   **labels**: setup, P1
   **milestone**: <FEATURE>
   **assignees**:
   **issue**:

   ### 目的
   <なぜこのタスクが必要か。spec.md の該当ユーザーストーリーを1〜2行で>

   ### 作業内容
   - <具体的な手順>

   ### 完了条件
   - [ ] <検証可能な条件>

   ### 参照
   - spec: `specs/<FEATURE>/spec.md`
   - plan: `specs/<FEATURE>/plan.md`
   - depends on: T000（なければ省略）
   ```

   Rules for the generated content:
   - **Leave `**issue**:` empty.** `push` fills it in; a filled value means "already created".
   - Write the body so someone who has not read `tasks.md` can still act on it.
   - Labels: derive from the task's phase/category in `tasks.md` (e.g. `setup`, `test`, `docs`)
     plus the user-story priority (`P1`/`P2`/…) when the task maps to one. Keep them short
     and lowercase; missing labels are created automatically on push.
   - `**milestone**:` defaults to the feature name so a feature's issues stay grouped.
   - Preserve `tasks.md` ordering, and record dependencies in the **参照** section —
     GitHub issues carry no ordering of their own.

5. Show the user a summary table (task ID → title → labels) and tell them to review
   `ISSUES_FILE`, then run `/speckit-issues push`. **Do not push in this mode.**

---

## Mode: Push

1. Preview first, and show the user the output:

   ```bash
   bash .specify/extensions/issues/scripts/bash/issues.sh push --dry-run
   ```

2. Ask the user to confirm, stating the target repository and how many issues will be created.
   Wait for approval — creating issues is an outward-facing action.

3. On approval:

   ```bash
   bash .specify/extensions/issues/scripts/bash/issues.sh push
   ```

   Pass `--limit N` through if the user asked to create only the first N.

4. Report the created issue numbers and URLs. The script has already written the numbers
   back into `ISSUES_FILE`; do not edit that file by hand afterwards.

Re-running `push` is safe: entries that already carry a number are skipped, and an issue
whose title already contains the task ID is adopted rather than duplicated.

---

## Mode: Status

```bash
bash .specify/extensions/issues/scripts/bash/issues.sh status
```

Show the table as-is and summarise what is pending.

---

## Mode: Branch

1. Extract the task ID (e.g. `T005`) from `$ARGUMENTS`.

2. ```bash
   bash .specify/extensions/issues/scripts/bash/issues.sh branch <TASK_ID>
   ```

   Accepted pass-through options: `--base <ref>` (default: the repo's default branch),
   `--name <branch-name>`, `--no-checkout`.

3. If it reports that no issue number is recorded, tell the user to run
   `/speckit-issues push` first — do not create the issue silently as a side effect.

4. After the branch is created, report the branch name and that it is linked to the issue,
   then suggest `/speckit-implement <TASK_ID>` to start the work.

> [!NOTE]
> `gh issue develop` pushes the new branch to the remote and links it to the issue,
> so the issue closes automatically when a PR from that branch is merged.

---

## Non-GitHub Trackers

If the user asks for Jira, Linear, Backlog, GitLab or another tracker, do **not** reuse
`issues.sh push` — it is GitHub-specific. Point them at the "他のタスク管理ツール" section
of `README.md`, which documents the adapter pattern: keep the same
`tasks.md → issues/issues.md → tracker` flow and swap only the push step.
