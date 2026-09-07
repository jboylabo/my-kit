# Spec Kit 導入ガイド（Flutter 実践編 + 他スタック）

モノレポではない**単体プロジェクト**に GitHub Spec Kit を導入する手順書です。
Flutter を主教材にして最後まで通し、後半で Swift / Next.js / Node.js への導入差分をまとめます。

> このリポジトリ（`my-kit`）自体の説明は [`../README.md`](../README.md) を参照してください。
> こちらは「別のプロジェクトに導入する」ための手順書です。

## 目次

1. [必要なもの](#1-必要なもの)
2. [環境構築](#2-環境構築)
3. [Flutter プロジェクトへの導入](#3-flutter-プロジェクトへの導入)
4. [初回の一周（憲法 → 仕様 → 計画 → タスク → 実装）](#4-初回の一周)
5. [拡張の追加](#5-拡張の追加)
6. [トラブルシューティング](#6-トラブルシューティング)
7. [他のスタックへの導入](#7-他のスタックへの導入)
8. [チートシート](#8-チートシート)

---

## 1. 必要なもの

### 必須

| ツール | 用途 | 確認コマンド |
|---|---|---|
| `uv` | `specify` CLI の実行 | `uv --version` |
| `git` | feature 管理・履歴 | `git --version` |
| Claude Code | スラッシュコマンドの実行環境 | `claude --version` |
| bash | `.specify/scripts/bash/*.sh` の実行 | macOS / Linux は標準 |

### Python について（よくある誤解）

**Python を自分でインストールする必要は基本的にありません。**

- `specify` CLI は `uv` が管理する Python 上で動きます。`uvx` が必要なバージョンを
  自動で取得するため、システムに Python が入っていなくても CLI は動作します。
- `.specify/scripts/bash/*.sh` は Python が**無くても**動くようフォールバックが用意されています。

ただし次の場合は `python3` が実際に必要になります。

| 状況 | Python の要否 |
|---|---|
| spec-kit の基本コマンドだけ使う | 不要（bash フォールバックあり） |
| `specify extension add` で拡張を入れた | **必要**（`.specify/extensions/.registry` の解決に使う） |
| `speckit-issues` 拡張（このリポジトリの自作）を使う | **必要** |

`common.sh` は `python3` → `python` → `py -3` の順に探します。
macOS は Xcode Command Line Tools に `python3` が含まれるため、Flutter 開発環境なら
たいてい既に入っています。

```bash
python3 --version   # 3.8 以上であれば十分
```

### 任意（使う機能に応じて）

| ツール | 必要になる場面 |
|---|---|
| `gh`（GitHub CLI） | `/speckit-issues` や `/speckit-taskstoissues` で Issue を作る |
| `jq` | スクリプトの JSON 出力を整形（無くても動作する） |
| Flutter SDK | 当然ながら Flutter 開発に |

---

## 2. 環境構築

### macOS

```bash
# uv
brew install uv

# GitHub CLI（Issue 連携を使うなら）
brew install gh
gh auth login

# python3（未導入なら。Xcode CLT に含まれる）
xcode-select --install
```

### Linux

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt install -y git python3 gh     # Debian / Ubuntu
```

### Windows

```powershell
winget install --id=astral-sh.uv -e
winget install --id GitHub.cli -e
```

Windows では `specify init` に `--script ps` を付けて PowerShell スクリプトを生成します
（後述のコマンドはすべて `--script sh` を `--script ps` に読み替えてください）。

### 動作確認

```bash
uv --version
uvx --from git+https://github.com/github/spec-kit.git specify check
```

`specify check` は **AI コーディングエージェントの導入状況だけ**を表示します
（git や Python はチェック対象外なので、上の表で自分で確認してください）。
`Claude Code (available)` と出れば準備完了です。

> `specify` はグローバルにインストールされません。`uvx` は「都度ダウンロードして実行」する
> 仕組みなので、`which specify` が空なのは正常です。

---

## 3. Flutter プロジェクトへの導入

### 3-1. 前提

単体リポジトリ（モノレポではない）の Flutter プロジェクトを想定します。

```
my_flutter_app/
├── lib/
├── test/
├── ios/
├── android/
└── pubspec.yaml
```

### 3-2. 初期化

**既存プロジェクトの中で `--here` を使うのがポイント**です。
`specify init <名前>` は新しいディレクトリを作ってしまうため、既存プロジェクトには使いません。

```bash
cd ~/dev/my_flutter_app

# git 管理下であることを確認（未初期化なら git init）
git status

uvx --from git+https://github.com/github/spec-kit.git specify init --here \
    --integration claude \
    --script sh
```

ディレクトリが空でない場合は確認プロンプトが出ます。内容を確認して続行してください
（確認を飛ばすなら `--force`。既存ファイルを上書きする可能性があるので、
コミットしていない変更が無い状態で実行することをおすすめします）。

### 3-3. 何が追加されるか

```
my_flutter_app/
├── .claude/skills/          # ← 追加: /speckit-* コマンド
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
├── .specify/                # ← 追加: テンプレート・スクリプト・憲法
│   ├── memory/constitution.md
│   ├── templates/
│   ├── scripts/bash/
│   └── ...
├── specs/                   # ← 機能ごとの spec/plan/tasks（初回は未作成）
├── lib/                     # 既存のまま
└── pubspec.yaml             # 既存のまま
```

**Flutter のファイルには一切手を加えません。** `pubspec.yaml` も `lib/` もそのままです。

### 3-4. `.specify` の位置が基準になる

spec-kit は「cwd から**上に**辿って最初に見つかった `.specify`」をプロジェクトルートとみなします。
`specs/` はその `.specify` と同じ階層に作られます。

単体プロジェクトではルートに1つだけ置けば良く、迷う余地はありません。

> 逆に、**ルートとサブディレクトリの両方に `.specify` を置くのは避けてください。**
> cwd 次第で `specs/` の行き先が変わり、混乱の元になります。

### 3-5. git にコミットするもの／しないもの

`.specify/.gitignore` が自動で配置され、マシン固有の状態は除外されます。

| 対象 | コミット | 理由 |
|---|---|---|
| `.claude/skills/` | **する** | チーム全員が同じコマンドを使えるように |
| `.specify/`（templates, scripts, memory） | **する** | 憲法とテンプレートは共有資産 |
| `.specify/feature.json` | しない（自動で除外済み） | 「今どの feature を見ているか」のローカル状態 |
| `specs/` | **する** | 仕様・計画・タスクは成果物そのもの |

```bash
git add .claude .specify specs
git commit -m "chore: introduce spec-kit"
```

---

## 4. 初回の一周

すべて **Claude Code のセッション内**でスラッシュコマンドとして実行します。
ターミナルで直接叩くコマンドではありません。

```
/speckit-constitution   → .specify/memory/constitution.md   最初に1回
        ↓
/speckit-specify        → specs/001-xxx/spec.md             何を作るか
        ↓
/speckit-clarify        → spec.md を更新                     曖昧点を潰す（推奨）
        ↓
/speckit-plan           → plan.md                           どう作るか
        ↓
/speckit-tasks          → tasks.md                          依存順のタスク
        ↓
/speckit-analyze        → レポート                           整合性チェック（非破壊）
        ↓
/speckit-implement      → 実際のコード
```

### 4-1. 憲法（Flutter 向けの書き方）

`/speckit-constitution` は以降のすべてのフェーズが参照する「守るべき原則」を作ります。
Flutter なら、後から揉めやすい判断を先に固定しておくと効果的です。

```
/speckit-constitution 状態管理は Riverpod に統一し、他のライブラリを導入しない。
機能は lib/features/<feature>/ 配下に閉じ、features 間の直接 import を禁止する。
すべての公開 Widget に widget test、すべての UseCase に unit test を用意する。
flutter analyze が警告ゼロで通ることをマージ条件とする。
新しい依存パッケージを追加するときは、代替案の検討結果を spec に記載する。
```

盛り込むと効く観点:

- **状態管理の固定**（Riverpod / Bloc / Provider のどれか1つ）— 一番揉める
- **ディレクトリ規約**（feature-first か layer-first か）
- **テスト方針**（widget test / unit test / golden test をどこまで必須にするか）
- **`flutter analyze` / `dart format` の扱い**
- **依存追加のルール**（パッケージが増えすぎる問題への予防線）
- **対応プラットフォーム**（iOS のみ / Android も / Web も）

### 4-2. 仕様

```
/speckit-specify お気に入りのカフェを地図上に保存して、タグとメモを付けて
後から絞り込めるモバイルアプリを作りたい。オフラインでも閲覧できること。
```

`specs/001-favorite-cafe-map/spec.md` が生成されます。
**この段階では技術の話を書きません。** ユーザーストーリーと受け入れ条件だけです。

続けて曖昧点を潰します。

```
/speckit-clarify
```

最大5問の質問が来るので答えてください。回答は `spec.md` に反映されます。

### 4-3. 計画（ここで初めて技術を決める）

```
/speckit-plan Flutter 3.x / Dart 3.x。状態管理は Riverpod（riverpod_generator）、
ルーティングは go_router、モデルは freezed + json_serializable。
ローカル保存は drift（SQLite）、地図は google_maps_flutter。
テストは flutter_test + mocktail。対応は iOS / Android のみ。
```

Flutter で `plan.md` に必ず書いておきたいこと:

| 項目 | 例 |
|---|---|
| Flutter / Dart のバージョン | `Flutter 3.24 / Dart 3.5` |
| 状態管理 | Riverpod（`@riverpod` コード生成を使うか否かも） |
| ルーティング | go_router / auto_route |
| モデル・シリアライズ | freezed + json_serializable |
| 永続化 | drift / isar / shared_preferences |
| ネットワーク | dio / http + retrofit |
| DI | Riverpod で兼ねる / get_it |
| テスト | flutter_test, mocktail, golden_toolkit |
| コード生成 | `dart run build_runner build --delete-conflicting-outputs` |
| ディレクトリ構成 | `lib/features/<name>/{presentation,application,domain,data}` |
| 対応プラットフォーム | iOS / Android |

**コード生成（build_runner）を使う場合は plan に明記してください。**
明記しないと `/speckit-implement` が生成対象ファイル（`*.freezed.dart`, `*.g.dart`）を
手書きしようとすることがあります。

### 4-4. タスクと実装

```
/speckit-tasks
/speckit-analyze
/speckit-implement
```

`/speckit-tasks` は `tasks.md` をユーザーストーリー単位のフェーズに分けて生成します
（Setup → Foundational → US1 → US2 → … → Polish）。
`/speckit-analyze` は spec / plan / tasks の矛盾を**変更せずに**報告します。

`/speckit-implement` は `tasks.md` を順に実行します。一気に全部やらせず、
フェーズごとに区切って確認するのがおすすめです。

```
/speckit-implement Phase 1 と Phase 2 だけ実行して
```

---

## 5. 拡張の追加

spec-kit には公式の拡張機構があります。**同梱・ローカル・URL・カタログ**の4経路で入ります。

```bash
E="uvx --from git+https://github.com/github/spec-kit.git specify"

$E extension list                 # 導入済みを確認
$E extension search jira          # カタログを検索（コミュニティ拡張は165件以上）
$E extension add git              # 同梱拡張を追加
$E extension add ./my-ext --dev   # ローカルディレクトリから
$E extension info git             # 詳細を見る
```

初期化と同時に入れることもできます。

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init --here \
    --integration claude --script sh \
    --extension git
```

### 入れておくと便利な同梱拡張

| 拡張 | 内容 |
|---|---|
| `git` | **フィーチャーブランチの自動作成**。素の spec-kit は `specs/` を作るだけでブランチを切らないので、ブランチ運用をするなら実質必須 |
| `agent-context` | `CLAUDE.md` などエージェント向け指示ファイルの管理 |
| `bug` | バグ報告を spec 化して修正・検証まで回す |
| `assess` | 本格着手前にアイデアを調査・評価する |

### Issue 連携

カタログには `github-issues` / `issue` / `tasks-to-project` / `jira` / `linear` などが揃っています。
まず既製品を試して、要件に合わなければ自作を検討してください。

このリポジトリで自作した `speckit-issues` 拡張を持ち込む場合は、2ディレクトリのコピーで動きます。

```bash
cd ~/dev/my_flutter_app
cp -r ~/dev/python-pj/speckit_example/my-kit/.specify/extensions/issues .specify/extensions/
cp -r ~/dev/python-pj/speckit_example/my-kit/.claude/skills/speckit-issues .claude/skills/
cp    ~/dev/python-pj/speckit_example/my-kit/.specify/extensions.yml       .specify/
```

`gh` の認証と GitHub リモートが必要です。使い方は [`../README.md` の 8章](../README.md) を参照。

---

## 6. トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `specify: command not found` | 正常。`uvx --from git+... specify ...` で都度実行する設計 |
| `/speckit-*` がコマンド一覧に出ない | Claude Code を再起動。`.claude/skills/` があるディレクトリで起動しているか確認 |
| `ERROR: Feature directory not found` | まだ feature が無い。`/speckit-specify` を先に実行 |
| `ERROR: Failed to resolve feature paths` | 同上。`/speckit-tasks` は spec.md と plan.md が前提 |
| 別 feature の spec が読まれる | `export SPECIFY_FEATURE=001-xxx` で明示 |
| `Feature directory already exists` | `--number N` か `--short-name` を変える |
| `Python 3 is required to honor the extension registry` | 拡張を入れると python3 が必須。`python3 --version` を確認 |
| `flutter analyze` が implement 後に落ちる | 憲法に「analyze 警告ゼロ」を入れておくと以後は考慮される |
| `*.g.dart` が無いとエラー | `dart run build_runner build --delete-conflicting-outputs` を実行。plan にコード生成を明記しておく |

状態を確認したいとき:

```bash
bash .specify/scripts/bash/check-prerequisites.sh --paths-only   # 現在の feature のパス
bash .specify/scripts/bash/check-prerequisites.sh --json         # 前提ファイルの有無
cat .specify/feature.json                                        # 今どの feature を見ているか
```

---

## 7. 他のスタックへの導入

導入コマンドはどのスタックでも同じです。**変わるのは憲法と plan の中身だけ**です。

```bash
cd <プロジェクトルート>
uvx --from git+https://github.com/github/spec-kit.git specify init --here \
    --integration claude --script sh
```

### 7-1. Swift / iOS（Xcode プロジェクト）

```
MyApp/
├── .specify/          ← ここに置く
├── .claude/skills/
├── specs/
├── MyApp.xcodeproj/
├── MyApp/
└── MyAppTests/
```

**憲法の例**

```
/speckit-constitution SwiftUI を標準とし、UIKit は既存画面の保守に限る。
アーキテクチャは MVVM + async/await。Combine は新規に使わない。
すべての ViewModel に XCTest のユニットテストを用意する。
外部依存は Swift Package Manager のみを使い、CocoaPods は追加しない。
SwiftLint の警告ゼロをマージ条件とする。
```

**plan で決めること**

| 項目 | 例 |
|---|---|
| 最低対応 OS | iOS 17.0+ |
| UI フレームワーク | SwiftUI / UIKit |
| 並行処理 | async/await + Actor |
| 永続化 | SwiftData / Core Data / GRDB |
| 依存管理 | Swift Package Manager |
| テスト | XCTest / Swift Testing |
| Lint | SwiftLint, swift-format |

**注意点**

- **`.xcodeproj` / `.pbxproj` は AI が直接編集すると壊れやすい**ため、
  「新規ファイルの Xcode プロジェクトへの追加は人間が行う」と憲法に書いておくと安全です。
  Swift Package Manager 中心の構成（`Package.swift`）にすると、この問題は大きく減ります。
- `/speckit-implement` の後は Xcode でビルドが通るか必ず確認してください。

### 7-2. Next.js

```
my-next-app/
├── .specify/
├── .claude/skills/
├── specs/
├── app/
├── package.json
└── next.config.ts
```

**憲法の例**

```
/speckit-constitution App Router のみを使い、Pages Router は追加しない。
デフォルトは Server Component とし、Client Component は必要な箇所に限定して
その理由をコメントに残す。データ取得は Server Actions に統一する。
型は any を禁止し、tsc --noEmit と eslint がエラーゼロで通ることをマージ条件とする。
UI は shadcn/ui + Tailwind に統一し、他の UI ライブラリを追加しない。
```

**plan で決めること**

| 項目 | 例 |
|---|---|
| Next.js / React バージョン | Next.js 15 / React 19 |
| ルーティング | App Router |
| データ取得 | Server Actions / Route Handlers |
| DB・ORM | PostgreSQL + Drizzle / Prisma |
| 認証 | Auth.js / Clerk |
| スタイリング | Tailwind + shadcn/ui |
| テスト | Vitest + Testing Library, Playwright |
| デプロイ | Vercel / Cloudflare |

**注意点**

- Server Component と Client Component の境界は spec ではなく **plan** に書きます。
  仕様書に `"use client"` の話を書き始めたら書きすぎです。
- `node_modules/` が巨大なので、`/speckit-analyze` などが遅く感じることがあります。

### 7-3. Node.js / TypeScript（API・CLI）

```
my-api/
├── .specify/
├── .claude/skills/
├── specs/
├── src/
└── package.json
```

**憲法の例**

```
/speckit-constitution TypeScript strict モードを有効にし、any と非 null アサーションを禁止する。
すべての公開関数に Vitest のユニットテストを用意し、カバレッジ 80% を下回らない。
外部 I/O（DB・HTTP・ファイル）は必ずインターフェース越しに呼び、テストで差し替え可能にする。
エラーは握りつぶさず、型付きの Result か例外で呼び出し元に伝播させる。
環境変数は zod でスキーマ検証してから使う。
```

**plan で決めること**

| 項目 | 例 |
|---|---|
| ランタイム | Node.js 22 LTS / Bun |
| パッケージマネージャ | pnpm / npm |
| フレームワーク | Hono / Fastify / Express |
| バリデーション | zod |
| DB・ORM | Drizzle / Prisma |
| テスト | Vitest, supertest |
| ビルド | tsup / tsc |
| Lint | ESLint + Prettier / Biome |

**注意点**

- CLI ツールなら、憲法に「stdin/args → stdout、エラーは stderr」「JSON と人間可読の両方を出す」
  と書いておくとテストしやすい設計に寄ります。

### 7-4. スタック別まとめ

| | Flutter | Swift/iOS | Next.js | Node.js |
|---|---|---|---|---|
| init コマンド | 全て共通（`specify init --here --integration claude --script sh`） | ← | ← | ← |
| 憲法で固定すべき筆頭 | 状態管理 | UI フレームワーク | Server/Client 境界 | 型の厳格さ |
| plan の必須項目 | コード生成(build_runner) | 最低対応 OS | App Router 前提 | ランタイム版数 |
| AI に触らせない方が良いもの | `*.g.dart`（生成物） | `.pbxproj` | `.next/` | `node_modules/` |
| implement 後の確認 | `flutter analyze && flutter test` | Xcode でビルド | `pnpm build && pnpm test` | `pnpm typecheck && pnpm test` |

---

## 8. チートシート

### 導入（1回だけ）

```bash
brew install uv gh                                    # macOS
cd <プロジェクトルート>
uvx --from git+https://github.com/github/spec-kit.git specify init --here \
    --integration claude --script sh --extension git
git add .claude .specify && git commit -m "chore: introduce spec-kit"
```

### 日々の流れ（Claude Code 内）

```
/speckit-constitution   # プロジェクトに1回
/speckit-specify  ...   # 機能ごとに
/speckit-clarify
/speckit-plan  ...
/speckit-tasks
/speckit-analyze
/speckit-implement
```

### シェルから確認するとき

```bash
bash .specify/scripts/bash/check-prerequisites.sh --paths-only
bash .specify/scripts/bash/create-new-feature.sh --dry-run --json "説明文"
cat .specify/memory/constitution.md
ls specs/
```

### CLI の管理

```bash
E="uvx --from git+https://github.com/github/spec-kit.git specify"
$E check                # エージェントの導入状況
$E extension list       # 拡張の一覧
$E extension search <q> # カタログ検索
$E --version
```

### 覚えておくと効く環境変数

| 変数 | 用途 |
|---|---|
| `SPECIFY_FEATURE` | 対象 feature を明示（複数機能を並行するとき） |
| `SPECIFY_FEATURE_DIRECTORY` | feature ディレクトリを直接指定 |
| `SPECIFY_INIT_DIR` | `.specify` を含むディレクトリを明示（モノレポでルートから叩くとき） |
