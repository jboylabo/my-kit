#!/usr/bin/env bash
# Spec Kit "issues" extension — tasks.md -> issues draft -> GitHub Issues -> branch.
#
#   issues.sh paths  [--json]                 Resolve feature/tasks/issues paths and repo slug
#   issues.sh init   [--force]                Create the issues draft scaffold
#   issues.sh status                          Show task -> issue mapping (local + remote state)
#   issues.sh push   [--dry-run] [--limit N]  Create GitHub issues for entries with no number
#   issues.sh branch <TASK_ID> [--base REF] [--name NAME] [--no-checkout]
#
# Every gh call is pinned to the slug derived from `git remote get-url origin`,
# so issues can never land in a repository other than this checkout's remote.

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_HELPER="$SCRIPT_DIR/../issues_md.py"
CORE_COMMON="$SCRIPT_DIR/../../../../scripts/bash/common.sh"

if [ ! -f "$CORE_COMMON" ]; then
    echo "Error: core common.sh not found at $CORE_COMMON" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CORE_COMMON"

WORKDIR=""
trap '[ -n "$WORKDIR" ] && rm -rf "$WORKDIR"' EXIT

die() { echo "Error: $*" >&2; exit 1; }
note() { echo "[issues] $*" >&2; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

# --- context resolution ------------------------------------------------------

REPO_ROOT="$(get_repo_root)" || exit 1
cd "$REPO_ROOT"

FEATURE_DIR=""
FEATURE_NAME=""
ISSUES_FILE=""
TASKS=""

# Resolved lazily: `--help` and usage errors must not require an active feature.
load_feature_context() {
    local paths
    if ! paths="$(get_feature_paths --no-persist)"; then
        die "no active feature. Run /speckit-specify (or set SPECIFY_FEATURE_DIRECTORY) first."
    fi
    eval "$paths"
    ISSUES_FILE="${SPECKIT_ISSUES_FILE:-$REPO_ROOT/issues/issues.md}"
    [[ "$ISSUES_FILE" != /* ]] && ISSUES_FILE="$REPO_ROOT/$ISSUES_FILE"
    FEATURE_NAME="$(basename "${FEATURE_DIR%/}")"
}

# Derive owner/name from the origin remote and refuse anything that is not GitHub.
resolve_repo_slug() {
    local url slug
    url="$(git config --get remote.origin.url 2>/dev/null || true)"
    [ -n "$url" ] || die "no 'origin' remote configured; GitHub issue creation needs one."

    case "$url" in
        git@github.com:*)         slug="${url#git@github.com:}" ;;
        ssh://git@github.com/*)   slug="${url#ssh://git@github.com/}" ;;
        https://github.com/*)     slug="${url#https://github.com/}" ;;
        http://github.com/*)      slug="${url#http://github.com/}" ;;
        *) die "remote origin is not a github.com URL: $url" ;;
    esac
    slug="${slug%.git}"
    slug="${slug%/}"
    case "$slug" in
        */*/*|*/) die "could not parse owner/name from remote: $url" ;;
        */*) : ;;
        *) die "could not parse owner/name from remote: $url" ;;
    esac
    printf '%s' "$slug"
}

# Guard: the draft file must belong to the feature we are currently on.
assert_feature_matches() {
    [ -f "$ISSUES_FILE" ] || return 0
    local declared
    declared="$(sed -n 's/^feature:[[:space:]]*//p' "$ISSUES_FILE" | head -1 | tr -d '[:space:]')"
    [ -n "$declared" ] || return 0
    if [ "$declared" != "$FEATURE_NAME" ]; then
        die "$ISSUES_FILE belongs to feature '$declared' but the current feature is '$FEATURE_NAME'.
       Archive it (e.g. mv issues/issues.md issues/$declared.md) or set SPECKIT_ISSUES_FILE."
    fi
}

# --- subcommands -------------------------------------------------------------

cmd_paths() {
    load_feature_context
    local json=false
    [ "${1:-}" = "--json" ] && json=true
    local slug=""
    slug="$(resolve_repo_slug 2>/dev/null || true)"

    if $json; then
        python3 - "$REPO_ROOT" "$FEATURE_NAME" "$FEATURE_DIR" "$TASKS" "$ISSUES_FILE" "$slug" <<'PY'
import json, sys
keys = ["REPO_ROOT", "FEATURE", "FEATURE_DIR", "TASKS", "ISSUES_FILE", "REPO_SLUG"]
print(json.dumps(dict(zip(keys, sys.argv[1:])), ensure_ascii=False))
PY
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "FEATURE: $FEATURE_NAME"
        echo "FEATURE_DIR: $FEATURE_DIR"
        echo "TASKS: $TASKS"
        echo "ISSUES_FILE: $ISSUES_FILE"
        echo "REPO_SLUG: ${slug:-(unresolved)}"
    fi
}

cmd_init() {
    load_feature_context
    local force=false
    [ "${1:-}" = "--force" ] && force=true

    [ -f "$TASKS" ] || die "tasks.md not found at $TASKS. Run /speckit-tasks first."
    if [ -f "$ISSUES_FILE" ] && [ -s "$ISSUES_FILE" ] && [ "$force" != true ]; then
        die "$ISSUES_FILE already exists and is not empty. Pass --force to overwrite."
    fi
    assert_feature_matches

    local template slug
    template="$SCRIPT_DIR/../../templates/issues-template.md"
    [ -f "$template" ] || die "template not found at $template"
    slug="$(resolve_repo_slug)"

    mkdir -p "$(dirname "$ISSUES_FILE")"
    sed -e "s|{{FEATURE}}|$FEATURE_NAME|g" \
        -e "s|{{SOURCE}}|${TASKS#$REPO_ROOT/}|g" \
        -e "s|{{REPO}}|$slug|g" \
        -e "s|{{GENERATED}}|$(date +%Y-%m-%d)|g" \
        "$template" > "$ISSUES_FILE"
    echo "Created $ISSUES_FILE"
}

cmd_status() {
    load_feature_context
    [ -f "$ISSUES_FILE" ] || die "$ISSUES_FILE not found. Run 'issues.sh init' first."
    assert_feature_matches
    local parsed
    parsed="$(mktemp)"
    python3 "$PY_HELPER" parse "$ISSUES_FILE" > "$parsed"
    python3 - "$parsed" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
entries = data["entries"]
if not entries:
    print("(no issue entries found)")
    raise SystemExit(0)
width = max(len(e["id"]) for e in entries)
pending = 0
for e in entries:
    state = e["issue_ref"] or "-- pending --"
    if not e["issue_ref"]:
        pending += 1
    print(f"{e['id']:<{width}}  {state:<13}  {e['title']}")
print(f"\n{len(entries)} entries, {pending} pending, {len(entries) - pending} pushed")
PY
    rm -f "$parsed"
}

cmd_push() {
    load_feature_context
    local dry_run=false limit=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --limit) shift; limit="${1:-0}" ;;
            *) die "unknown option for push: $1" ;;
        esac
        shift
    done

    require_cmd gh
    [ -f "$ISSUES_FILE" ] || die "$ISSUES_FILE not found. Run 'issues.sh init' first."
    assert_feature_matches

    local slug
    slug="$(resolve_repo_slug)"
    # `gh auth status` fails when *any* stored account has a stale token, so probe
    # the active account only (falling back to an API call on older gh versions).
    gh auth status --active >/dev/null 2>&1 || gh api user >/dev/null 2>&1 \
        || die "gh is not authenticated. Run: gh auth login"
    note "target repository: $slug"

    WORKDIR="$(mktemp -d)"
    local work="$WORKDIR"

    local ids
    ids="$(python3 "$PY_HELPER" export "$ISSUES_FILE" --out-dir "$work" --pending)"
    if [ -z "$ids" ]; then
        echo "Nothing to push: every entry already has an issue number."
        return 0
    fi

    # One remote read covers deduplication for every task ID.
    gh issue list --repo "$slug" --state all --limit 500 --json number,title > "$work/.existing.json" 2>/dev/null \
        || echo '[]' > "$work/.existing.json"

    local -a set_args=()
    local created=0 adopted=0 processed=0

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if [ "$limit" -gt 0 ] && [ "$processed" -ge "$limit" ]; then
            note "reached --limit $limit; stopping."
            break
        fi
        processed=$((processed + 1))

        local title existing
        title="$(cat "$work/$id.title")"
        [ -n "$title" ] || die "$id has an empty title in $ISSUES_FILE"

        # Adopt an existing issue whose title carries this task ID.
        existing="$(python3 - "$work/.existing.json" "$id" <<'PY'
import json, re, sys
path, task_id = sys.argv[1], sys.argv[2]
pattern = re.compile(r"(?<![0-9A-Za-z_])" + re.escape(task_id) + r"(?![0-9A-Za-z_])")
for issue in json.load(open(path, encoding="utf-8")):
    if pattern.search(issue.get("title", "")):
        print(issue["number"])
        break
PY
)"
        if [ -n "$existing" ]; then
            echo "  $id -> #$existing (already exists, adopting)"
            set_args+=("--set" "$id=$existing")
            adopted=$((adopted + 1))
            continue
        fi

        local -a gh_args=(--repo "$slug" --title "$id: $title")
        if [ -s "$work/$id.body" ]; then
            gh_args+=(--body-file "$work/$id.body")
        else
            gh_args+=(--body "Generated from \`${TASKS#$REPO_ROOT/}\` (task $id).")
        fi

        local label assignee milestone
        while IFS= read -r label || [ -n "$label" ]; do
            [ -n "$label" ] || continue
            if [ "$dry_run" != true ]; then
                gh label create "$label" --repo "$slug" --force >/dev/null 2>&1 || true
            fi
            gh_args+=(--label "$label")
        done < "$work/$id.labels"

        while IFS= read -r assignee || [ -n "$assignee" ]; do
            [ -n "$assignee" ] || continue
            gh_args+=(--assignee "$assignee")
        done < "$work/$id.assignees"

        milestone="$(cat "$work/$id.milestone")"
        if [ -n "$milestone" ]; then
            if [ "$dry_run" != true ]; then
                gh api "repos/$slug/milestones" -f title="$milestone" >/dev/null 2>&1 || true
            fi
            gh_args+=(--milestone "$milestone")
        fi

        if [ "$dry_run" = true ]; then
            echo "  [dry-run] $id: $title"
            printf '            gh issue create'; printf ' %q' "${gh_args[@]}"; printf '\n'
            continue
        fi

        local url number
        url="$(gh issue create "${gh_args[@]}")" || die "failed to create issue for $id"
        number="${url##*/}"
        echo "  $id -> #$number  $url"
        set_args+=("--set" "$id=$number")
        created=$((created + 1))
    done <<< "$ids"

    if [ ${#set_args[@]} -gt 0 ]; then
        python3 "$PY_HELPER" update "$ISSUES_FILE" "${set_args[@]}"
    fi
    if [ "$dry_run" = true ]; then
        echo "Dry run complete. Nothing was created."
    else
        echo "Created $created issue(s), adopted $adopted existing."
    fi
}

cmd_branch() {
    load_feature_context
    local task_id="" base="" name="" checkout=true
    while [ $# -gt 0 ]; do
        case "$1" in
            --base) shift; base="${1:-}" ;;
            --name) shift; name="${1:-}" ;;
            --no-checkout) checkout=false ;;
            -*) die "unknown option for branch: $1" ;;
            *) task_id="$1" ;;
        esac
        shift
    done
    [ -n "$task_id" ] || die "usage: issues.sh branch <TASK_ID> [--base REF] [--name NAME] [--no-checkout]"

    require_cmd gh
    [ -f "$ISSUES_FILE" ] || die "$ISSUES_FILE not found. Run 'issues.sh init' first."
    assert_feature_matches

    local slug number
    slug="$(resolve_repo_slug)"
    number="$(python3 - "$ISSUES_FILE" "$task_id" "$PY_HELPER" <<'PY'
import json, subprocess, sys
issues_file, task_id, helper = sys.argv[1], sys.argv[2], sys.argv[3]
out = subprocess.run([sys.executable, helper, "parse", issues_file],
                     capture_output=True, text=True, check=True).stdout
for entry in json.loads(out)["entries"]:
    if entry["id"].lower() == task_id.lower() and entry["issue"]:
        print(entry["issue"])
        break
PY
)"
    [ -n "$number" ] || die "no issue number recorded for '$task_id'. Run 'issues.sh push' first."

    if [ -z "$base" ]; then
        base="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)"
    fi

    local -a dev_args=("$number" --repo "$slug" --base "$base")
    [ -n "$name" ] && dev_args+=(--name "$name")
    [ "$checkout" = true ] && dev_args+=(--checkout)

    note "creating a branch linked to issue #$number (base: $base)"
    gh issue develop "${dev_args[@]}"
    if [ "$checkout" = true ]; then
        echo "Now on: $(git rev-parse --abbrev-ref HEAD)"
    fi
}

# --- dispatch ----------------------------------------------------------------

case "${1:-}" in
    paths)  shift; cmd_paths "$@" ;;
    init)   shift; cmd_init "$@" ;;
    status) shift; cmd_status "$@" ;;
    push)   shift; cmd_push "$@" ;;
    branch) shift; cmd_branch "$@" ;;
    ""|-h|--help)
        sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;
    *) die "unknown subcommand '$1'. Run with --help." ;;
esac
