# EventKit の変更検知と ScreenTime 制限チェック - バックグラウンド動作について

## 概要

EventKit の変更を検知し、リマインダーを再読み込みする際に、ScreenTime 制限の条件を自動的に再評価する機能を実装しました。

## 実装内容

### 1. EventKit 変更検知の処理

`TaskModel.swift` の `EventKitTaskManager` クラスに以下の機能を追加：

```swift
// EventKitの変更通知を監視
private func setupEventStoreNotifications() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(eventStoreChanged),
        name: .EKEventStoreChanged,
        object: eventStore
    )
}

// EventKitの変更を検知した時の処理
@objc private func eventStoreChanged() {
    DispatchQueue.main.async {
        print("EventKitの変更を検知しました - リマインダーを再読み込みします")
        self.loadReminders()

        // リマインダー再読み込み後、ScreenTime制限条件を再評価
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.evaluateScreenTimeRestrictionAfterReload()
        }
    }
}
```

### 2. ScreenTime 制限条件の再評価

EventKit 変更後に以下の処理を実行：

1. **タスク更新の処理** (`handleTaskUpdate()`)

   - UWB Secure Bubble 内にいる場合、タスクの時刻条件に基づいて制限を有効化/無効化
   - 当日のタスクがあり、時刻が到来している場合に制限を有効化

2. **タスク完了状態の確認** (`handleTaskCompletion()`)
   - 制限が有効な状態で、すべてのタスクが完了している場合は制限を解除
   - 未完了タスクが残っている場合は制限を継続

## バックグラウンド動作について

### EventKit 変更通知のバックグラウンド動作

#### ✅ バックグラウンドで動作する部分

1. **EventKit 変更通知 (.EKEventStoreChanged)**

   - iOS 標準の通知メカニズムで、バックグラウンドでも動作します
   - 他のアプリ（標準リマインダーアプリなど）でタスクが変更された場合も検知されます
   - アプリがバックグラウンド状態でも通知は受信されます

2. **リマインダーの再読み込み**
   - `eventStore.fetchReminders()` はバックグラウンドでも実行可能
   - ただし、バックグラウンド実行時間の制限があります（通常 30 秒程度）

#### ⚠️ 制限がある部分

1. **ScreenTime 制限の変更**

   - `ManagedSettingsStore` の変更は、アプリがフォアグラウンドまたはバックグラウンド実行中に可能
   - ただし、アプリが完全に終了（suspended 状態）している場合は実行されません

2. **バックグラウンド実行時間**
   - iOS はバックグラウンドでの CPU 使用を制限します
   - 長時間の処理は完了前に中断される可能性があります

### バックグラウンド動作の挙動

#### シナリオ 1: アプリがフォアグラウンド

- ✅ EventKit 変更を即座に検知
- ✅ リマインダーを再読み込み
- ✅ ScreenTime 制限を即座に更新
- **結果**: すべて正常に動作

#### シナリオ 2: アプリがバックグラウンド（実行中）

- ✅ EventKit 変更を検知
- ✅ リマインダーを再読み込み
- ✅ ScreenTime 制限を更新（30 秒以内なら実行可能）
- **結果**: 基本的に正常に動作

#### シナリオ 3: アプリが完全に終了（suspended）

- ⚠️ EventKit 変更通知は受信されない
- ❌ リマインダーの再読み込みは実行されない
- ❌ ScreenTime 制限は更新されない
- **結果**: アプリを再起動するまで更新されない

#### シナリオ 4: アプリ再起動時

- ✅ `onAppear` で各マネージャーの参照が設定される
- ✅ 初回の `loadReminders()` が実行される
- ✅ ScreenTime 制限条件が再評価される
- **結果**: アプリ起動時に最新の状態に同期

### バックグラウンドタスクによる定期チェック

現在の実装では、以下のバックグラウンドタスクが登録されています：

```swift
// AppDelegate.swift
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.locationreminder.app.screentime.monitoring",
    using: nil
) { task in
    // ScreenTime監視タスク
}
```

このタスクは定期的に実行され、以下を行います：

- UWB 状態とタスク状況をチェック
- 必要に応じて ScreenTime 制限を有効化/無効化

### 推奨される運用

1. **通常運用**

   - アプリをバックグラウンドで実行し続ける（完全終了しない）
   - これにより、EventKit 変更を継続的に検知できます

2. **定期的な同期**

   - アプリを定期的にフォアグラウンドに持ってくる
   - または、バックグラウンドタスクの実行を待つ

3. **手動更新**
   - プルツーリフレッシュで手動更新が可能
   - アプリ起動時に自動的に最新の状態に同期

## 技術的な詳細

### 実装されているチェック処理

1. **タスク時刻条件チェック** (`shouldEnableRestrictionBasedOnTasks()`)

   - 当日のタスクが存在するか
   - 未完了のタスクがあるか
   - 時刻が設定されているタスクの場合、時刻が到来しているか

2. **UWB 状態チェック**

   - Secure Bubble 内にいるか
   - デバイスが接続されているか

3. **完了状態チェック**
   - すべてのタスクが完了しているか
   - 制限を解除すべきか

### ログ出力

以下のログが出力され、動作を追跡できます：

```
EventKitの変更を検知しました - リマインダーを再読み込みします
📋 EventKit変更後: ScreenTime制限条件を再評価します

=== 📝 タスク更新時の制限チェック ===
📅 当日のタスク総数: X
📊 未完了タスク数: Y
...

=== 📋 タスク完了時の制限チェック ===
📊 当日のタスク総数: X
📊 未完了タスク数: Y
📊 現在の制限状態: 有効/無効
...
✅ ScreenTime制限条件の再評価が完了しました
```

## まとめ

- EventKit 変更検知は**バックグラウンドでも動作**しますが、完全に終了している場合は動作しません
- ScreenTime 制限の更新は**バックグラウンド実行中は可能**です
- 最も確実な動作のためには、アプリをバックグラウンドで実行し続けることを推奨します
- アプリ起動時には自動的に最新の状態に同期されます
