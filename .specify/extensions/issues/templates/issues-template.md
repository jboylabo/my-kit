---
feature: {{FEATURE}}
source: {{SOURCE}}
repo: {{REPO}}
generated: {{GENERATED}}
---

# Issues — {{FEATURE}}

GitHub に登録する Issue の**下書き**です。ここを編集してから push してください。

- `/speckit-issues push` — `**issue**:` が空のエントリだけを GitHub に作成し、番号を書き戻します
- `/speckit-issues branch T001` — 記録済みの Issue に紐づくブランチを作成して checkout します

<!-- speckit:summary -->
| Task | Issue | Title |
| --- | --- | --- |
<!-- speckit:summary-end -->

## 書式

1エントリは `speckit:issue` マーカーで始まり、次のマーカー（または EOF）までが1件です。

    <!-- speckit:issue id=T001 -->
    ## T001 — Create the project skeleton

    **labels**: setup, P1
    **milestone**: {{FEATURE}}
    **assignees**:
    **issue**:

    ここから下が Issue の本文になります。Markdown をそのまま書けます。

- 見出し `## T001 — <タイトル>` の `<タイトル>` が Issue タイトルになります
  （実際のタイトルは `T001: <タイトル>` の形で作成されます）
- `**issue**:` は空のままにしておきます。push 後に `#12` のように自動で埋まります
- 空欄は `**assignees**:` のように値なし、または `—` / `-` と書けます
- 番号が入った行は push の対象外になるため、再実行しても二重登録されません

---
