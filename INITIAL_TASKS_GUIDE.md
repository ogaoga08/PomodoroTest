# 初期タスク設定ガイド

## 概要

このアプリでは、初回起動時に「実験用リスト」というリマインダーリストを自動作成し、以下の初期タスクを登録します：

- **英単語課題**: 1〜14 日目まで各 17:00（14 タスク）
- **一般教養課題**: 1〜14 日目まで各 17:00（14 タスク）
- **動画視聴課題**: 4 日目と 11 日目の 17:00（2 タスク）

合計 30 タスクが自動生成されます。

## 初期タスクの追加・編集方法

### 1. タスクの種類を追加する

`LocationReminderApp/Models/TaskModel.swift`の`InitialTaskType`列挙型にタスク種類を追加します：

```swift
enum InitialTaskType: String, CaseIterable {
    case vocabulary = "英単語課題"
    case generalKnowledge = "一般教養課題"
    case videoWatching = "動画視聴課題"
    case newTaskType = "新しいタスク種類"  // ← 追加

    var displayName: String {
        return rawValue
    }
}
```

### 2. 初期タスクの生成ロジックを編集する

`TaskModel.swift`の`InitialTaskGenerator.generateInitialTasks(from:)`メソッド内で、タスク生成ロジックを変更できます。

#### 例 1: 新しいタスク種類を毎日追加する

```swift
// 1日目から14日目まで繰り返し
for day in 1...14 {
    // 既存のコード...

    // 新しいタスク種類を追加（毎日）
    tasks.append(InitialTaskData(
        type: .newTaskType,
        dayNumber: day,
        title: "新しいタスク\(day)日目",
        memo: dummyURL,
        dueDate: taskDate
    ))
}
```

#### 例 2: 特定の日にのみタスクを追加する

```swift
// 動画視聴課題の例（4日目と11日目のみ）
if day == 4 || day == 11 {
    tasks.append(InitialTaskData(
        type: .videoWatching,
        dayNumber: day,
        title: "動画視聴課題",
        memo: dummyURL,
        dueDate: taskDate
    ))
}

// 新しい例: 7日目と14日目にアンケート課題を追加
if day == 7 || day == 14 {
    tasks.append(InitialTaskData(
        type: .survey,
        dayNumber: day,
        title: "アンケート\(day)日目",
        memo: "https://forms.google.com/survey",
        dueDate: taskDate
    ))
}
```

### 3. タスクの時刻を変更する

現在は 17:00 に設定されていますが、変更する場合：

```swift
// 現在のコード
components.hour = 17
components.minute = 0

// 例: 9:00に変更
components.hour = 9
components.minute = 0

// 例: タスク種類によって時刻を変える
components.hour = (day % 2 == 0) ? 17 : 9  // 偶数日は17:00、奇数日は9:00
components.minute = 0
```

### 4. メモ欄の URL を変更する（重要）

**URL は日ごとに異なるように設定されています。** `TaskModel.swift`の`InitialTaskGenerator`構造体内にある 3 つの URL 生成メソッドを編集してください：

#### 4-1. 英単語課題の URL 設定

`getVocabularyURL(for:)`メソッドを編集：

```swift
private static func getVocabularyURL(for day: Int) -> String {
    // switch文を使って日ごとに異なるURLを返す
    switch day {
    case 1: return "https://forms.google.com/d/e/実際のID1/viewform"
    case 2: return "https://forms.google.com/d/e/実際のID2/viewform"
    case 3: return "https://forms.google.com/d/e/実際のID3/viewform"
    case 4: return "https://forms.google.com/d/e/実際のID4/viewform"
    case 5: return "https://forms.google.com/d/e/実際のID5/viewform"
    case 6: return "https://forms.google.com/d/e/実際のID6/viewform"
    case 7: return "https://forms.google.com/d/e/実際のID7/viewform"
    case 8: return "https://forms.google.com/d/e/実際のID8/viewform"
    case 9: return "https://forms.google.com/d/e/実際のID9/viewform"
    case 10: return "https://forms.google.com/d/e/実際のID10/viewform"
    case 11: return "https://forms.google.com/d/e/実際のID11/viewform"
    case 12: return "https://forms.google.com/d/e/実際のID12/viewform"
    case 13: return "https://forms.google.com/d/e/実際のID13/viewform"
    case 14: return "https://forms.google.com/d/e/実際のID14/viewform"
    default: return "https://forms.google.com/vocabulary-day\(day)"
    }
}
```

#### 4-2. 一般教養課題の URL 設定

`getGeneralKnowledgeURL(for:)`メソッドを編集：

```swift
private static func getGeneralKnowledgeURL(for day: Int) -> String {
    switch day {
    case 1: return "https://forms.google.com/d/e/知識ID1/viewform"
    case 2: return "https://forms.google.com/d/e/知識ID2/viewform"
    // ... 14日分設定
    case 14: return "https://forms.google.com/d/e/知識ID14/viewform"
    default: return "https://forms.google.com/knowledge-day\(day)"
    }
}
```

#### 4-3. 動画視聴課題の URL 設定

`getVideoWatchingURL(for:)`メソッドを編集：

```swift
private static func getVideoWatchingURL(for day: Int) -> String {
    switch day {
    case 4: return "https://forms.google.com/d/e/動画ID4/viewform"
    case 11: return "https://forms.google.com/d/e/動画ID11/viewform"
    default: return "https://forms.google.com/video-day\(day)"
    }
}
```

#### 4-4. URL が同じパターンの場合

もし URL が規則的なパターン（例: パラメータで日数を指定）の場合：

```swift
private static func getVocabularyURL(for day: Int) -> String {
    // クエリパラメータで日数を指定する場合
    return "https://forms.google.com/d/e/固定ID/viewform?entry.123456=\(day)"
}
```

### 5. タスクの日数を変更する

14 日間から別の日数に変更：

```swift
// 現在のコード
for day in 1...14 {

// 例: 21日間に変更
for day in 1...21 {

// 例: 7日間に変更
for day in 1...7 {
```

### 6. 優先度や繰り返し設定を追加する

`InitialTaskData`構造体を拡張して、優先度や繰り返し設定を追加できます：

```swift
struct InitialTaskData {
    let type: InitialTaskType
    let dayNumber: Int
    let title: String
    let memo: String
    let dueDate: Date
    let priority: TaskPriority = .none     // ← 追加
    let recurrence: RecurrenceType = .none  // ← 追加

    func toTaskItem() -> TaskItem {
        return TaskItem(
            title: title,
            memo: memo,
            dueDate: dueDate,
            hasTime: true,
            priority: priority,      // ← 使用
            recurrenceType: recurrence  // ← 使用
        )
    }
}
```

使用例：

```swift
tasks.append(InitialTaskData(
    type: .vocabulary,
    dayNumber: day,
    title: "英単語課題\(day)日目",
    memo: vocabularyFormURL,
    dueDate: taskDate,
    priority: .high,       // 高優先度
    recurrence: .none      // 繰り返しなし
))
```

## 初期タスクの動作フロー

1. **初回起動時**:

   - オンボーディング画面が表示される
   - 各種権限のリクエストが行われる

2. **オンボーディング完了後**:

   - 初期タスクが未作成の場合、`InitialTaskSetupView`が自動表示される
   - ユーザーが 1 日目の日付を選択する（デフォルトは当日）

3. **タスク作成ボタン押下時**:

   - 「実験用リスト」が作成される
   - 選択された日付を起点に初期タスクが一括生成される
   - EventKit（iOS 標準リマインダー）に登録される

4. **完了後**:
   - 通常のタスクリスト画面に戻る
   - 作成されたタスクが表示される

## 初期化フラグのリセット

テストや再実行のために初期タスクを再作成したい場合：

1. アプリをアンインストール
2. または、以下の UserDefaults キーを削除：
   - `HasCreatedInitialTasks`
   - `hasCompletedOnboarding`

開発中は、Xcode の「Reset Content and Settings」でシミュレータをリセットするのが最も簡単です。

## 関連ファイル

- `LocationReminderApp/Models/TaskModel.swift`: 初期タスクのデータ構造と生成ロジック
- `LocationReminderApp/Views/InitialTaskSetupView.swift`: 開始日選択画面の UI
- `LocationReminderApp/ContentView.swift`: アプリフローの統合

## 注意事項

- 初期タスクは一度だけ作成されます（`HasCreatedInitialTasks`フラグで管理）
- タスクは実際の iOS 標準リマインダーアプリにも表示されます
- 「実験用リスト」は自動的に選択されたリマインダーリストとして設定されます
