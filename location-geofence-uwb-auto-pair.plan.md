# EventKit 位置情報リマインダーによる UWB 自動ペアリング

## 背景と目的

**問題**: アプリ独自のジオフェンス監視（`CLLocationManager`）を使用すると、バックグラウンドで常に位置情報利用ラベルが画面左上に表示されてしまう

**解決策**: EventKit の位置情報リマインダーを利用することで、この問題を回避しつつ、位置トリガーで UWB 自動ペアリングを実現

## 実装状況

### ✅ Phase 1: EventKit アプローチ - 実装完了

EventKit の位置情報リマインダーの通知/イベントをトリガーとして使用

### 🔄 Phase 2: 実機テスト - 次のステップ

実機でのテストと動作確認

### ⏳ Phase 3: フォールバック（必要に応じて）

EventKit アプローチが技術的に困難な場合、既存の`UWBManager`ジオフェンス機能を強化

---

## 実装完了した機能

### 1. 位置情報リマインダー通知の検知

**ファイル**: `UWBSettingsView.swift` (NotificationManager 拡張)

- ✅ `isLocationReminderNotification()`: 位置情報リマインダー通知を判定
  - `[uwb_auto_trigger]`マーカーでの識別
  - リマインダーアプリのカテゴリ ID での識別
- ✅ `handleLocationReminderNotificationReceived()`: 通知受信時の処理
  - UWBManager.startAutoPairing()を呼び出し
- ✅ フォアグラウンド・バックグラウンド両方で動作

### 2. 自宅位置情報タスクの作成・管理

**ファイル**: `TaskModel.swift` (EventKitTaskManager)

- ✅ `createOrUpdateHomeLocationTask()`: 自宅タスクを作成/更新
  - タイトル: 「自宅（UWB 自動接続用）」
  - メモ: `[uwb_auto_trigger]`マーカー付き
  - 位置トリガー: `.arriving`（到着時）
  - 半径: 50m（デフォルト）
- ✅ `deleteHomeLocationTask()`: 自宅タスクを削除

### 3. UWB 自動ペアリング

**ファイル**: `UWBSettingsView.swift` (UWBManager)

- ✅ `startAutoPairing(triggeredBy:)`: EventKit トリガー用の自動ペアリング
  - 保存済みデバイスの読み込み
  - Bluetooth スキャン開始
  - 各ステップで通知送信
  - 60 秒のタイムアウト処理

### 4. 統合処理

**ファイル**: `PermissionManager.swift`, `GeofencingSettingsView.swift`, `MenuView.swift`

- ✅ `PermissionManager`: 位置情報許可取得時に自宅タスクを自動作成
- ✅ `GeofencingSettingsView`: 手動で自宅設定時にもタスクを作成
- ✅ `MenuView`: GeofencingSettingsView への EnvironmentObject 注入

---

## 処理フロー

### 【初回セットアップ】

```
1. ユーザーが位置情報許可を付与
   ↓
2. PermissionManagerが現在地を取得
   ↓
3. EventKitに自宅タスクを作成
   - タイトル: 「自宅（UWB自動接続用）」
   - 位置トリガー: 到着時、半径50m
   - メモ: [uwb_auto_trigger]マーカー
```

### 【通常動作】

```
1. ユーザーが自宅に到着
   ↓
2. iOS が位置トリガーを検知
   ↓
3. リマインダー通知が発火
   ↓
4. NotificationManagerが通知を受信
   - isLocationReminderNotification()で判定
   ↓
5. handleLocationReminderNotificationReceived()実行
   ↓
6. UWBManager.startAutoPairing()呼び出し
   ↓
7. 保存済みUWBデバイスをスキャン・接続
   ↓
8. 各ステップで進捗通知を送信
   - "🏠 帰宅を検知"
   - "📡 デバイスをスキャン中"
   - "📱 UWB接続開始"
   - "✅ UWBペアリング成功"
   - "📏 距離測定開始"
```

---

## 実機テスト手順

### 準備

1. ✅ UWB デバイスを事前にペアリングして保存
2. ✅ 位置情報許可を「常に許可」に設定
3. ✅ 通知許可を有効化
4. ✅ リマインダー許可を有効化

### テスト 1: 自宅タスクの作成確認

1. GeofencingSettingsView で自宅位置を設定
2. リマインダーアプリを開く
3. 「自宅（UWB 自動接続用）」タスクが作成されているか確認
4. タスクの位置情報設定を確認（到着時、半径 50m）

### テスト 2: 位置トリガーの動作確認

1. 自宅から離れる（半径 50m 以上）
2. 自宅に戻る
3. リマインダー通知が表示されるか確認
4. ログで UWBManager.startAutoPairing()が呼ばれているか確認

### テスト 3: UWB 自動ペアリングの確認

1. 自宅に到着
2. 進捗通知が順次表示されるか確認
   - "🏠 帰宅を検知"
   - "📡 デバイスをスキャン中"
   - "📱 UWB 接続開始"
   - "✅ UWB ペアリング成功"
   - "📏 距離測定開始"
3. UWB 設定画面で ranging 状態になっているか確認
4. 距離測定が開始されているか確認

### テスト 4: バックグラウンド動作の確認

1. アプリをバックグラウンドに移動
2. 自宅に到着
3. バックグラウンドで通知が表示されるか確認
4. UWB 自動ペアリングが実行されるか確認

### テスト 5: エラーハンドリングの確認

1. UWB デバイスの電源をオフにする
2. 自宅に到着
3. タイムアウト通知（60 秒後）が表示されるか確認

---

## 成功条件

- ✅ 実装完了: EventKit ベースの UWB 自動ペアリング機能
- 🔄 テスト中: 実機での動作確認
- ⏳ 評価待ち: 位置情報ラベルが常時表示されないか確認
- ⏳ 評価待ち: バックグラウンドでの確実な動作

---

## 次のステップ

### 1. 実機テスト

- [ ] 自宅タスクの作成を確認
- [ ] 位置トリガーの動作を確認
- [ ] UWB 自動ペアリングを確認
- [ ] バックグラウンド動作を確認
- [ ] エラーハンドリングを確認

### 2. 改善点の洗い出し

- [ ] 位置情報ラベルの表示状況を確認
- [ ] バックグラウンド動作の信頼性を評価
- [ ] 通知の内容・タイミングを最適化

### 3. フォールバック判断

- EventKit アプローチで問題がある場合、アプリ独自ジオフェンスに切り替え

---

## Phase 2: フォールバックアプローチ（必要時のみ）

EventKit アプローチが技術的に困難な場合、既存の`UWBManager`ジオフェンス機能を強化

### 実装内容

1. `handleHomeEntry()`の改善
2. 通知システムの統合
3. 自動ペアリング状態管理
4. タイムアウト処理とエラーハンドリング

**注**: ユーザーの指示があった場合のみ実装
