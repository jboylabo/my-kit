# my-kit — GitHub Spec Kit 実践メモ

[Spec Kit](https://github.com/github/spec-kit) は「仕様(spec)を先に書き、そこから計画・タスク・実装をAIに生成させる」
**Spec-Driven Development (SDD)** のツールキットです。
このリポジトリは Claude Code 連携 (`--integration claude`) で初期化済みです。

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
│   └── speckit-taskstoissues/SKILL.md
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
│   ├── init-options.json           # init 時の選択内容（ai=claude, script=sh など）
│   ├── integration.json            # 有効な連携先
│   └── .gitignore                  # feature.json 等のローカル状態を除外
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
