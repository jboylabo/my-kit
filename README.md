# my-kit — GitHub Spec Kit 実践メモ

[Spec Kit](https://github.com/github/spec-kit) は「仕様(spec)を先に書き、そこから計画・タスク・実装をAIに生成させる」
**Spec-Driven Development (SDD)** のツールキットです。
このリポジトリは Claude Code 連携 (`--integration claude`) で初期化済みです。

> **他のプロジェクトに導入したい場合** → [`examples/README.md`](examples/README.md)
> Flutter を主教材にした導入手順書です。環境構築から初回の一周まで通しで解説し、
> Swift / Next.js / Node.js への導入差分も載せています。

---

## 1. セットアップ（実行済みの内容）

```bash
# 1. uv (Python パッケージ/ツールランナー) を入れる
brew install uv

# 2. Spec Kit の CLI (specify) を一時実行してプロジェクトを初期化
uvx --from git+https://github.com/github/spec-kit.git specify init my-kit --integration claude
```

- `uvx` は「インストールせずにコマンドを一発実行する」uv のサブコマンド。
  `specify` 本体はグローバルに入らないので `which specify` しても出てこないのが正常です。
- カレントディレクトリを直接初期化したい場合は `specify init --here --integration claude`。
- 後から更新したいときは同じコマンドを再実行（`.specify/integrations/*.manifest.json` の
  ハッシュで差分管理されるため、自分で編集したファイルは保護されます）。

### 前提ツール

| ツール | 用途 | 必須か |
|---|---|---|
| `uv` / `uvx` | `specify` CLI の実行 | 必須 |
| `git` | feature 管理・履歴 | ほぼ必須 |
| `bash` | `.specify/scripts/bash/*.sh` の実行 | 必須（macOS 標準でOK） |
| `jq` | スクリプトの JSON 出力を整形（なくても動く） | 任意 |

---

## 2. ディレクトリ構成

```
my-kit/
├── .claude/skills/            # Claude Code から呼べるスラッシュコマンド（10個）
│   ├── speckit-constitution/SKILL.md
│   ├── speckit-specify/SKILL.md
│   ├── speckit-clarify/SKILL.md
│   ├── speckit-plan/SKILL.md
│   ├── speckit-tasks/SKILL.md
│   ├── speckit-analyze/SKILL.md
│   ├── speckit-checklist/SKILL.md
│   ├── speckit-implement/SKILL.md
│   ├── speckit-converge/SKILL.md
│   ├── speckit-taskstoissues/SKILL.md
│   └── speckit-issues/SKILL.md        # ← このリポジトリで追加した自作コマンド
├── .specify/
│   ├── memory/constitution.md      # プロジェクト憲法（全フェーズが参照する原則）
│   ├── templates/                  # spec / plan / tasks / checklist の雛形
│   │   ├── spec-template.md
│   │   ├── plan-template.md
│   │   ├── tasks-template.md
│   │   └── checklist-template.md
│   ├── scripts/bash/               # スキルが内部で叩くシェルスクリプト
│   │   ├── create-new-feature.sh   # specs/NNN-xxx/ を作り spec.md を配置
│   │   ├── setup-plan.sh           # plan.md を配置
│   │   ├── setup-tasks.sh          # tasks.md を配置
│   │   ├── check-prerequisites.sh  # 前提ファイルの有無チェック＆パス出力
│   │   ├── resolve-template.sh     # テンプレート解決（拡張のオーバーライド対応）
│   │   └── common.sh               # 共通関数（リポジトリルート検出など）
│   ├── workflows/speckit/workflow.yml  # specify→plan→tasks→implement の一括ワークフロー定義
│   ├── extensions.yml              # 拡張フックの登録（after_tasks で issues を提案）
│   ├── extensions/issues/          # ← GitHub Issue 連携の自作拡張（8章）
│   │   ├── extension.yml
│   │   ├── scripts/issues_md.py    #   issues.md のパース／番号書き戻し
│   │   ├── scripts/bash/issues.sh  #   init / status / push / branch
│   │   └── templates/issues-template.md
│   ├── init-options.json           # init 時の選択内容（ai=claude, script=sh など）
│   ├── integration.json            # 有効な連携先
│   └── .gitignore                  # feature.json 等のローカル状態を除外
├── issues/
│   └── issues.md                   # ← Issue の下書き（GitHub 登録前のレビュー用）
└── specs/                          # ← 機能ごとの成果物がここに増えていく（初回は未作成）
    └── 001-your-feature/
        ├── spec.md      # 何を作るか（What / Why）
        ├── plan.md      # どう作るか（技術選定・設計）
        ├── tasks.md     # 実行可能なタスク一覧（依存順）
        └── checklists/  # 任意
```

---

## 3. 基本ワークフロー

**すべて Claude Code のセッション内でスラッシュコマンドとして実行します。**
（ターミナルで直接叩くコマンドではありません。スクリプトはスキルが裏で呼びます）

```
/speckit-constitution   ← 最初に1回。プロジェクトの原則を決める
        ↓
/speckit-specify        ← 機能の仕様を書く（specs/001-xxx/spec.md 生成）
        ↓
/speckit-clarify        ← 仕様の曖昧点を質問形式で潰す（推奨）
        ↓
/speckit-plan           ← 技術設計・実装計画（plan.md 生成）
        ↓
/speckit-tasks          ← 依存順のタスク分解（tasks.md 生成）
        ↓
/speckit-analyze        ← spec/plan/tasks の整合性チェック（非破壊）
        ↓
/speckit-implement      ← tasks.md を順に実行して実装
```

### 各コマンドの役割

| コマンド | 役割 | 出力 |
|---|---|---|
| `/speckit-constitution` | プロジェクトの憲法（守るべき原則）を作成・更新 | `.specify/memory/constitution.md` |
| `/speckit-specify` | 自然言語の要望 → 仕様書。ユーザーストーリーを P1/P2… で優先度付け | `specs/NNN-name/spec.md` |
| `/speckit-clarify` | 仕様の曖昧箇所を最大5問ヒアリングし、回答を spec.md に反映 | `spec.md` 更新 |
| `/speckit-plan` | アーキテクチャ・技術選定・データモデル等の設計 | `plan.md` ほか設計成果物 |
| `/speckit-tasks` | 実装タスクを依存順に分解 | `tasks.md` |
| `/speckit-analyze` | spec / plan / tasks の矛盾・抜けを検出（変更はしない） | レポート |
| `/speckit-checklist` | 「要件の単体テスト」= 要件品質チェックリストを生成 | `checklists/*.md` |
| `/speckit-implement` | tasks.md のタスクを実行して実際にコードを書く | ソースコード |
| `/speckit-converge` | 既存コードと spec/plan の差分を見て、未実装分を tasks.md に追記 | `tasks.md` 追記 |
| `/speckit-taskstoissues` | tasks.md を GitHub Issue 群に変換 | GitHub Issues |
| `/speckit-issues` | **（自作）** tasks.md → Issue 下書き → GitHub 登録 → ブランチ作成 | `issues/issues.md`, GitHub Issues, ブランチ |

### 使用例

```
/speckit-constitution テスト駆動を必須とし、外部依存は最小限に保つ。CLI は JSON と人間可読の両方を出す

/speckit-specify Markdown のメモをタグで分類して全文検索できる CLI ツールを作りたい

/speckit-clarify

/speckit-plan Python 3.12 + Typer + SQLite FTS5 を使う。外部サービス依存なし

/speckit-tasks

/speckit-analyze

/speckit-implement
```

---

## 4. シェルスクリプトについて

`.specify/scripts/bash/*.sh` は **スキルが自動で呼ぶ**もので、通常は手で実行しません。
ただし挙動を理解したり、デバッグしたいときは直接叩けます。

```bash
# 何が作られるか、実際には作らずに確認（dry-run）
bash .specify/scripts/bash/create-new-feature.sh --dry-run --json "Add tag search to notes CLI"
# → {"BRANCH_NAME":"001-tag-search-notes-cli","SPEC_FILE":".../specs/001-tag-search-notes-cli/spec.md","FEATURE_NUM":"001","DRY_RUN":true}

# 現在の feature のパス一覧だけ取得（検証なし）
bash .specify/scripts/bash/check-prerequisites.sh --paths-only

# implement フェーズの前提（plan.md + tasks.md）が揃っているか確認
bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks

# ヘルプ
bash .specify/scripts/bash/create-new-feature.sh --help
```

### 主なポイント

- **feature 番号は自動採番**：`specs/` 配下の既存ディレクトリの最大値 +1（`001`, `002`, …）。
  `--number 5` で指定、`--timestamp` で `YYYYMMDD-HHMMSS` 形式に切り替え可。
- **ブランチ名は説明文から自動生成**：ストップワード（the, add, for など）を除去し、
  意味のある単語 3〜4 個を `-` で連結。`--short-name user-auth` で明示指定もできる。
- **このバージョンの `create-new-feature.sh` は git ブランチを作りません**。
  `specs/NNN-xxx/` ディレクトリの作成と `.specify/feature.json` への記録のみ。
  ブランチ運用は自分で `git switch -c 001-xxx` するか、git 拡張を入れます。
- **「今どの feature を見ているか」の解決順**：
  1. 環境変数 `SPECIFY_FEATURE` / `SPECIFY_FEATURE_DIRECTORY`
  2. `.specify/feature.json`（`create-new-feature.sh` が書く。`.gitignore` 済み）
  3. 現在の git ブランチ名

  複数 feature を並行させるときは明示的に指定すると安全：
  ```bash
  export SPECIFY_FEATURE=001-tag-search-notes
  ```
- **モノレポなどで cd せずに実行**したい場合は `SPECIFY_INIT_DIR` に
  `.specify/` を含むディレクトリの絶対パスを渡します。

---

## 5. 一括実行ワークフロー

`.specify/workflows/speckit/workflow.yml` に、
`specify → (レビュー) → plan → (レビュー) → tasks → implement` を
承認ゲート付きで通す定義が入っています。
各ゲートで approve / reject を選び、reject すると中断（abort）します。

段階ごとに確認したい場合は、上記のスラッシュコマンドを1つずつ実行する方が細かく制御できます。

---

## 6. つまずきやすい点

| 症状 | 対処 |
|---|---|
| `specify: command not found` | 正常。`uvx --from git+... specify ...` で都度実行する設計 |
| スラッシュコマンドが出てこない | Claude Code を再起動、または `/speckit-` と打って補完を確認 |
| `Feature directory already exists` | `--number N` で番号を変える、`--short-name` を変える、または `--allow-existing-branch` |
| 別 feature の spec が読まれる | `export SPECIFY_FEATURE=NNN-name` で明示 |
| spec がふわっとしていて plan が的外れ | `/speckit-clarify` を挟む。`/speckit-analyze` で整合性も検査 |
| 途中まで手で実装済みのコードがある | `/speckit-converge` で未実装分だけタスク化 |

---

## 7. 最初の一歩

```bash
# まだコミットが1つもないので、初期化直後の状態を記録しておく
git add -A && git commit -m "chore: initialize spec-kit (claude integration)"
```

そのあと Claude Code で：

```
/speckit-constitution
```

から始めるのがおすすめです。憲法を先に決めておくと、以降の spec / plan / tasks が
すべてその原則に沿って生成されます。

---

## 8. GitHub Issue 連携（`/speckit-issues`）— 自作コマンド

`tasks.md` を GitHub の Issue にし、着手時に Issue 連動ブランチを切るまでを担当します。
標準の `/speckit-taskstoissues` との違いは次の3点です。

| | `/speckit-taskstoissues`（標準） | `/speckit-issues`（自作） |
|---|---|---|
| 実行手段 | GitHub MCP サーバー | `gh` CLI（追加設定不要） |
| レビュー | なし。tasks.md から直接作成 | `issues/issues.md` に下書き → 人が確認 → push |
| ブランチ | なし | `gh issue develop` で Issue 連動ブランチを作成 |

### 使い方

```
/speckit-tasks                 # 前提: tasks.md ができていること
        ↓
/speckit-issues                # ① 下書き: issues/issues.md を生成（GitHubには触らない）
        ↓ 人が中身をレビュー・編集
/speckit-issues push           # ② 登録: Issue を作成し、#番号を issues.md に書き戻す
        ↓
/speckit-issues T005           # ③ 着手: Issue #N に紐づくブランチを作って checkout
        ↓
/speckit-implement T005        # ④ 実装
```

- `/speckit-issues status` — どのタスクがどの Issue になったかを一覧表示
- `push` は必ず `--dry-run` のプレビューと確認を挟んでから実行されます

### 安全設計

- **リポジトリの固定**: すべての `gh` 呼び出しに `--repo <slug>` を付けます。slug は
  `git remote get-url origin` から導出し、github.com 以外なら即エラー。別リポジトリに
  Issue が飛ぶことがありません。
- **二重登録の防止**: `**issue**:` に番号が入った行は push 対象外。加えて push 前に
  既存 Issue を1回だけ取得し、タイトルにタスクID（`T001` 等）を含む Issue があれば
  新規作成せずその番号を採用します。`tasks.md` を作り直しても重複しません。
- **feature の取り違え防止**: `issues.md` の `feature:` が現在の feature と違う場合は停止します。

### シェルから直接使う

スキルは下記スクリプトを呼んでいるだけなので、手動でも実行できます。

```bash
EXT=.specify/extensions/issues/scripts/bash/issues.sh

bash $EXT paths --json        # feature / tasks.md / issues.md / repo slug を解決
bash $EXT init                # 下書きの雛形を作成（中身の生成は Claude の担当）
bash $EXT status              # タスク → Issue の対応表
bash $EXT push --dry-run      # 実行される gh コマンドを確認するだけ
bash $EXT push --limit 5      # 先頭5件だけ登録
bash $EXT branch T005 --base main
```

環境変数:

| 変数 | 用途 |
|---|---|
| `SPECKIT_ISSUES_FILE` | 下書きファイルの場所を変更（既定 `issues/issues.md`） |
| `SPECIFY_FEATURE_DIRECTORY` | 対象 feature を明示（既定は `.specify/feature.json`） |

### `issues/issues.md` の書式

1エントリは `speckit:issue` マーカーで始まり、次のマーカーまでが1件です。

```
<!-- speckit:issue id=T001 -->
## T001 — Create the project skeleton

**labels**: setup, P1
**milestone**: 001-tag-search-notes-cli
**assignees**:
**issue**:

### 目的
plan.md のディレクトリ構成に合わせて雛形を用意する。

### 完了条件
- [ ] src/ と tests/ が存在する
```

- Issue タイトルは `T001: Create the project skeleton` の形で作成されます
- `**issue**:` は空のままに。push 後に `#12` が自動で入り、以後は対象外になります
- 存在しないラベル・マイルストーンは push 時に自動作成されます

---

## 9. 他のタスク管理ツール（Jira / Linear / Backlog / GitLab）

`/speckit-issues` は `gh` に依存しているので、GitHub 以外ではそのまま使えません。
ただし**差し替えるのは push の一手だけ**です。

```
tasks.md  ──►  issues/issues.md  ──►  [ push アダプタ ]  ──►  各トラッカー
（Spec Kit が生成）  （ツール非依存の中間形式）   ここだけ入れ替える
```

`issues/issues.md` はトラッカー非依存の形式なので、①下書き生成（Claude）と
③書き戻し（`issues_md.py update`）はそのまま再利用でき、②の API 呼び出しだけを書けば済みます。
`**issue**:` 欄は数値以外も受け付けるため、Jira の `ABC-123` や Linear の `ENG-45` を
そのまま記録できます。

### ツールごとに変わるのはこの4点

| | GitHub | Jira Cloud | Linear | Backlog | GitLab |
|---|---|---|---|---|---|
| 認証 | `gh auth login` | メール + API トークン (Basic) | API キー (`Authorization`) | APIキー (`?apiKey=`) | `glab auth login` |
| 作成API | `gh issue create` | `POST /rest/api/2/issue` | GraphQL `issueCreate` | `POST /api/v2/issues` | `glab issue create` |
| 識別子 | `#12` | `ABC-123` | `ENG-45` | `PRJ-7` | `#12` |
| ブランチ連携 | `gh issue develop`（自動リンク） | 手動。ブランチ名にキーを含める | ブランチ名にIDを含める | 手動 | `glab issue create` 後に手動 |

### 例: Jira Cloud 用アダプタ

`.specify/extensions/issues/scripts/bash/jira-push.sh` として置く想定のテンプレートです。
（Jira インスタンスがないため未検証です。プロジェクトキーとフィールド構成に合わせて調整してください）

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${JIRA_SITE:?例: your-team.atlassian.net}"
: "${JIRA_EMAIL:?Atlassian アカウントのメールアドレス}"
: "${JIRA_API_TOKEN:?https://id.atlassian.com/manage-profile/security/api-tokens で発行}"
: "${JIRA_PROJECT_KEY:?例: ABC}"
JIRA_ISSUE_TYPE="${JIRA_ISSUE_TYPE:-Task}"

ROOT="$(git rev-parse --show-toplevel)"
HELPER="$ROOT/.specify/extensions/issues/scripts/issues_md.py"
ISSUES_FILE="${SPECKIT_ISSUES_FILE:-$ROOT/issues/issues.md}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ① 未登録エントリだけを取り出す（GitHub 版と全く同じ仕組みを再利用）
ids="$(python3 "$HELPER" export "$ISSUES_FILE" --out-dir "$WORK" --pending)"
[ -n "$ids" ] || { echo "登録対象はありません"; exit 0; }

set_args=()
while IFS= read -r id || [ -n "$id" ]; do
    [ -n "$id" ] || continue

    # ② Jira の課題作成 API を叩く
    payload="$(python3 - "$JIRA_PROJECT_KEY" "$JIRA_ISSUE_TYPE" \
                        "$id: $(cat "$WORK/$id.title")" \
                        "$WORK/$id.body" "$WORK/$id.labels" <<'PY'
import json, sys
project, issuetype, summary, body_path, labels_path = sys.argv[1:6]
description = open(body_path, encoding="utf-8").read()
labels = [l.replace(" ", "-") for l in
          open(labels_path, encoding="utf-8").read().splitlines() if l]
print(json.dumps({"fields": {
    "project":     {"key": project},
    "issuetype":   {"name": issuetype},
    "summary":     summary,
    "description": description,   # REST v2 はプレーンテキストでよい
    "labels":      labels,        # Jira のラベルに空白は使えない
}}))
PY
)"

    response="$(curl -sS -X POST \
        -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$payload" \
        "https://$JIRA_SITE/rest/api/2/issue")"

    key="$(printf '%s' "$response" \
           | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))')"
    if [ -z "$key" ]; then
        echo "失敗 $id: $response" >&2
        continue
    fi
    echo "  $id -> $key  https://$JIRA_SITE/browse/$key"
    set_args+=(--set "$id=$key")
done <<< "$ids"

# ③ 課題キーを issues.md に書き戻す（GitHub 版と共通）
if [ ${#set_args[@]} -gt 0 ]; then
    python3 "$HELPER" update "$ISSUES_FILE" "${set_args[@]}"
fi
```

実行:

```bash
export JIRA_SITE=your-team.atlassian.net
export JIRA_EMAIL=you@example.com
export JIRA_API_TOKEN=xxxxxxxx
export JIRA_PROJECT_KEY=ABC
bash .specify/extensions/issues/scripts/bash/jira-push.sh
```

#### Jira でのハマりどころ

- **REST v3 は description が ADF（Atlassian Document Format）**になります。プレーンテキストを
  渡すと 400 になるので、v2 を使うか ADF に変換してください。
  ```json
  "description": {
    "type": "doc", "version": 1,
    "content": [{"type": "paragraph",
                 "content": [{"type": "text", "text": "本文"}]}]
  }
  ```
- **ラベルに空白は使えません**。`P1 setup` のような値は `-` に置換します。
- **必須カスタムフィールド**（Epic Link、Story Points 等）がプロジェクトに設定されていると
  作成が弾かれます。`GET /rest/api/2/issue/createmeta?projectKeys=ABC&expand=projects.issuetypes.fields`
  で必須フィールドを確認してから `fields` に追加してください。
- **タスクの依存関係**は Jira の課題リンクで表現できます（`POST /rest/api/2/issueLink`、
  `type: {"name": "Blocks"}`）。まず全件作成してキーを確定させ、その後リンクを張る2パス構成にします。

#### ブランチ作成（GitHub 以外）

`gh issue develop` に相当するものが無いので、手で切ります。ブランチ名にキーを含めておくと
Jira / Linear 側が自動で紐づけてくれます（GitHub for Jira アプリや Linear の GitHub 連携が前提）。

```bash
git switch -c ABC-123-create-project-skeleton
# コミットメッセージにもキーを入れると Smart Commit が効く
git commit -m "ABC-123 プロジェクト雛形を作成"
```

### 例: Linear（GraphQL）

`②` の部分だけ差し替えます。

```bash
curl -sS -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H 'Content-Type: application/json' \
  --data "$(python3 - "$LINEAR_TEAM_ID" "$id: $title" "$WORK/$id.body" <<'PY'
import json, sys
team_id, title, body_path = sys.argv[1:4]
print(json.dumps({
    "query": """mutation($input: IssueCreateInput!) {
                  issueCreate(input: $input) { issue { identifier url } }
                }""",
    "variables": {"input": {
        "teamId":      team_id,
        "title":       title,
        "description": open(body_path, encoding="utf-8").read(),
    }},
}))
PY
)"
# 返り値 data.issueCreate.issue.identifier（例: ENG-45）を --set に渡す
```

### 例: Backlog / GitLab

```bash
# Backlog: プロジェクトIDと課題種別IDは事前に API で引いておく
curl -sS -X POST "https://$BACKLOG_SPACE/api/v2/issues?apiKey=$BACKLOG_API_KEY" \
     --data-urlencode "projectId=$BACKLOG_PROJECT_ID" \
     --data-urlencode "issueTypeId=$BACKLOG_ISSUE_TYPE_ID" \
     --data-urlencode "priorityId=3" \
     --data-urlencode "summary=$id: $title" \
     --data-urlencode "description@$WORK/$id.body"
# 返り値 .issueKey（例: PRJ-7）

# GitLab: gh とほぼ同じ感覚で使える
glab issue create --title "$id: $title" --description "$(cat "$WORK/$id.body")" --label setup
```

### 自作アダプタを Claude から呼べるようにする

`.claude/skills/speckit-issues/SKILL.md` をコピーして
`.claude/skills/speckit-jira/SKILL.md` を作り、**Mode: Push** のコマンドだけを
`jira-push.sh` に差し替えれば `/speckit-jira` として使えます。
Draft / Status / Branch の各モードはトラッカーに依存しないのでそのまま流用できます。
