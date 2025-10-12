# ジオフェンス・UWB・Screen Time 処理プロセス分析

## 📋 概要

LocationReminder アプリの 3 つの主要処理（ジオフェンス、UWB、Screen Time）の統合状況と動作プロセスを説明します。

---

## 🎯 1. ジオフェンス処理

### 実装状況

✅ **実装完了・動作確認済み**

### 処理フロー

```
1. 自宅位置設定
   └─ GeofencingSettingsView で自宅位置を選択
      └─ UWBManager.setHomeLocation() を呼び出し
         └─ UserDefaultsに保存（座標、住所、半径）
            └─ setupGeofencing() で監視開始

2. ジオフェンス監視
   └─ CLLocationManager が地域監視を実行
      └─ CLCircularRegion（半径50-100m）
         ├─ 進入検知: didEnterRegion
         └─ 退出検知: didExitRegion

3. イベント処理
   ├─ 【進入時】handleHomeEntry()
   │   ├─ デバッグ通知送信（有効時）
   │   ├─ UWBスキャン自動開始
   │   ├─ バックグラウンドセッション開始
   │   └─ Screen Time準備
   │
   └─ 【退出時】handleHomeExit()
       ├─ デバッグ通知送信（有効時）
       ├─ UWB処理停止
       └─ Screen Time制限無効化
```

### 設定項目

| 項目             | 設定値       | 説明                          |
| ---------------- | ------------ | ----------------------------- |
| ジオフェンス半径 | 50m（固定）  | GeofencingSettingsView で設定 |
| 自動再接続       | オン（固定） | 帰宅時の UWB 自動接続         |
| デバッグ通知     | トグル可能   | 進入/退出時の通知             |

### 保存データ（UserDefaults）

- `homeLatitude`: 自宅の緯度
- `homeLongitude`: 自宅の経度
- `homeAddress`: 自宅の住所
- `homeRadius`: ジオフェンス半径
- `geofenceDebugNotificationEnabled`: デバッグ通知有効/無効

---

## 📡 2. UWB 処理 (Secure Bubble 機能)

### 実装状況

✅ **実装完了・動作確認済み**

### Secure Bubble とは

UWB デバイスとの距離に基づいて、ユーザーが「作業範囲内」にいるかを判定する機能

### 処理フロー

```
1. UWBデバイス接続
   └─ Bluetoothスキャン（QorvoNIService）
      └─ デバイス発見・接続
         └─ NISession開始
            └─ 距離測定開始

2. Secure Bubble判定
   ├─ 距離 ≤ 0.2m → Bubble内
   ├─ 距離 ≥ 1.2m → Bubble外
   └─ 0.2m < 距離 < 1.2m → 前回の状態を維持（ヒステリシス）

3. 状態変化イベント
   └─ isInSecureBubble プロパティ更新
      ├─ セッション記録（統計用）
      ├─ 通知送信（有効時）
      └─ Screen Time制限切り替え
```

### しきい値設定

| 状態      | 距離       | 説明                   |
| --------- | ---------- | ---------------------- |
| Bubble 内 | ≤ 0.2m     | デバイスの近く         |
| Bubble 外 | ≥ 1.2m     | デバイスから離れている |
| 中間      | 0.2m〜1.2m | ヒステリシス領域       |

### バックグラウンド処理（指数バックオフ方式）

- **自宅内**: BGTaskScheduler が指数バックオフで実行
  - **初回**: 1 分後
  - **2 回目**: 2 分後
  - **3 回目**: 4 分後
  - **4 回目**: 8 分後
  - **5 回目**: 16 分後
  - **6 回目**: 32 分後
  - **最大**: 60 分間隔
- **リセット条件**:
  - ジオフェンス進入時（帰宅時）
  - UWB 接続切断時
  - バックグラウンドタスク失敗時
- **自宅外**: 軽量なハートビート監視
- **距離更新停止時**: 自動修復（フォアグラウンド: 15 秒、バックグラウンド: 60 秒）

**メリット**: 帰宅直後は頻繁に再接続を試み、時間経過とともに間隔を延ばしてバッテリーを節約

### 位置情報監視の最適化（🆕 追加機能）

- **UWB 接続時**: ジオフェンス監視を一時停止（位置情報「常に使用」ラベル非表示）
- **UWB 切断時**: ジオフェンス監視を自動再開（帰宅検知のため）
- **メリット**: ユーザーの不安解消 + バッテリー節約

---

## 🛡️ 3. Screen Time 処理

### 実装状況

✅ **実装完了・動作確認済み**

### 制限有効化の条件（AND 条件）

```
制限有効 = UWB Secure Bubble内
         AND 当日のタスクあり
         AND タスク時刻到来（時刻設定タスクの場合）
```

### 処理フロー

```
1. 状態監視
   ├─ UWB状態変化
   │   └─ ContentView.onReceive(uwbManager.$isInSecureBubble)
   │      └─ 2秒後に状態確認（チャタリング防止）
   │         └─ Screen Time切り替え
   │
   ├─ タスク更新
   │   └─ NotificationCenter.post(.taskUpdated)
   │      └─ handleTaskUpdate()
   │         └─ 制限条件再評価
   │
   └─ タスク完了
       └─ handleTaskCompletion()
          └─ 未完了タスクなし → 制限解除

2. 制限有効化
   └─ enableRestrictionForSecureBubble()
      ├─ shouldEnableRestrictionBasedOnTasks()
      │   ├─ 当日のタスク確認
      │   ├─ 未完了タスク抽出
      │   └─ 時刻条件チェック
      │
      └─ enableRestriction()
          ├─ store.clearAllSettings()
          ├─ アプリ制限設定
          ├─ カテゴリ制限設定
          └─ Webドメイン制限設定

3. 制限無効化
   └─ disableRestrictionForSecureBubble()
      └─ disableRestriction()
         ├─ store.clearAllSettings()
         └─ セッション記録
```

### タスク時刻条件

| タスクタイプ     | 制限タイミング |
| ---------------- | -------------- |
| 時刻設定あり     | タスク時刻以降 |
| 時刻設定なし     | 当日中常に     |
| 未完了タスクなし | 制限なし       |

### バックグラウンド処理

- **1 分間隔**: タスク時刻監視（taskTimeMonitorTimer）
- **1 秒間隔**: 認証状態監視（authStatusMonitorTimer）
- **BGTask**: バックグラウンドメンテナンスタスク

---

## 🔄 統合プロセス全体像

```
【自宅外】
  ↓
ジオフェンス進入検知
  ↓
UWBスキャン自動開始
  ↓
UWBデバイス接続
  ↓
Secure Bubble監視開始
  ↓
【Bubble内に進入】
  ↓
タスク条件チェック
  ├─ 当日タスクあり + 時刻到来 → Screen Time制限有効化 ✅
  └─ 条件不満足 → 制限なし ⭕
  ↓
【Bubble外に退出】
  ↓
Screen Time制限無効化
  ↓
【自宅外に退出】
  ↓
UWB処理停止・Screen Time無効化
```

---

## 🔔 デバッグ通知機能

### 実装内容

- **GeofencingSettingsView**: ジオフェンス進入/退出の通知トグル
- **UWBSettingsView**: UWB ペアリング処理の通知トグル

### 通知タイミング

#### ジオフェンス通知

| イベント         | 通知タイトル        | 通知内容                                                   |
| ---------------- | ------------------- | ---------------------------------------------------------- |
| ジオフェンス進入 | 🏠 ジオフェンス進入 | 自宅エリアに入りました。UWB 再接続を開始します。           |
| ジオフェンス退出 | 🚪 ジオフェンス退出 | 自宅エリアから離れました。Screen Time 制限を無効化します。 |

#### UWB ペアリング通知

| イベント           | 通知タイトル          | 通知内容                             |
| ------------------ | --------------------- | ------------------------------------ |
| Bluetooth 接続開始 | 📱 UWB 接続開始       | Bluetooth 接続を開始します           |
| NI セッション開始  | 🔄 UWB ペアリング開始 | NI セッション設定を送信します        |
| ペアリング成功     | ✅ UWB ペアリング成功 | デバイスとのペアリングが完了しました |
| Bluetooth 接続失敗 | ❌ UWB 接続失敗       | Bluetooth 接続に失敗しました         |
| NI セッション切断  | ⚠️ UWB セッション切断 | NI セッションが無効化されました      |

### 使用方法

#### ジオフェンス通知

1. `GeofencingSettingsView`を開く
2. 「ジオフェンシング状態」セクションの「デバッグ通知」をオン
3. ジオフェンス範囲を出入りすると通知が届く

#### UWB ペアリング通知

1. `UWBSettingsView`を開く
2. 「UWB ペアリング通知」トグルをオン
3. UWB デバイスとの接続・切断時に通知が届く

### 通知許可

通知を受け取るには、以下の許可が必要：

- 通知許可（UserNotifications）
- 位置情報許可（Always）

---

## ✅ 修正・追加した内容

### GeofencingSettingsView.swift

1. ✅ UWBManager 参照を追加
2. ✅ ジオフェンス状態表示セクション追加
   - ジオフェンス設定状態
   - 位置情報監視状態（🆕 UWB 使用中は一時停止と表示）
   - 在宅状態
   - デバッグ通知トグル
3. ✅ saveHomeLocation()で UWBManager に自宅位置を通知
4. ✅ loadSavedData()でデバッグ通知設定を復元

### UWBSettingsView.swift

1. ✅ `geofenceDebugNotificationEnabled`プロパティ追加
2. ✅ `geofencingMonitoring`プロパティ追加（🆕 実際の監視状態を追跡）
3. ✅ `homeRadius`を変数に変更（設定可能に）
4. ✅ `setHomeLocation(coordinate:address:radius:)`オーバーロード追加
5. ✅ `setGeofenceDebugNotification(enabled:)`メソッド追加
6. ✅ `sendGeofenceDebugNotification(title:message:)`メソッド追加
7. ✅ handleHomeEntry()を改善（🆕 必ず自動接続を試みる + 指数バックオフ方式）
8. ✅ handleHomeExit()にデバッグ通知追加
9. ✅ loadHomeLocation()で半径とデバッグ設定を復元
10. ✅ `pauseGeofenceMonitoring()`メソッド追加（🆕 UWB 接続時に位置情報監視を停止）
11. ✅ `resumeGeofenceMonitoring()`メソッド追加（🆕 UWB 切断時に位置情報監視を再開）
12. ✅ UWB 距離更新時に自動的にジオフェンス監視を一時停止
13. ✅ UWB セッション切断時に自動的にジオフェンス監視を再開
14. ✅ BG タスク指数バックオフ実装（🆕 1 分 →2 分 →4 分 →...→ 最大 60 分）
15. ✅ `increaseBackgroundTaskInterval()`メソッド追加（🆕 間隔を 2 倍に延長）
16. ✅ `resetBackgroundTaskInterval()`メソッド追加（🆕 間隔を 1 分にリセット）
17. ✅ BG タスク成功時に自動的に間隔を延長
18. ✅ UWB 切断時・ジオフェンス進入時・退出時に間隔をリセット
19. ✅ `uwbPairingDebugNotificationEnabled`プロパティ追加（🆕 UWB ペアリングデバッグ通知）
20. ✅ `setUWBPairingDebugNotification(enabled:)`メソッド追加（🆕 通知設定）
21. ✅ `sendUWBPairingDebugNotification(title:message:deviceName:)`メソッド追加（🆕 通知送信）
22. ✅ Bluetooth 接続開始時にデバッグ通知を送信
23. ✅ NI セッション設定送信時にデバッグ通知を送信
24. ✅ ペアリング成功時にデバッグ通知を送信
25. ✅ Bluetooth 接続失敗時にデバッグ通知を送信
26. ✅ NI セッション切断時にデバッグ通知を送信
27. ✅ UWBSettingsView にペアリングデバッグ通知トグルを追加

---

## 🐛 デバッグ方法

### 1. ログ確認

Xcode のコンソールで以下のログを確認：

```
🏠 ジオフェンス進入: 自宅エリア進入 - UWB再接続開始
📍 距離: 0.15m | Bubble: 内部 | ScreenTime: 有効
🔒 UWB Secure Bubble内 + 当日タスクあり - 制限有効化
```

### 2. 状態表示

- **GeofencingSettingsView**: ジオフェンス監視・在宅状態
- **UWBSettingsView**: UWB 接続・Secure Bubble 状態
- **ScreenTimeSettingsView**: 制限有効・UWB 連動状態

### 3. デバッグ通知

ジオフェンス進入/退出時にリアルタイムで通知を受信

### 4. 統計データ

- **StatisticsView**: 在室時間・不在時間・休憩回数

---

## 📝 注意事項

### 位置情報許可

- ✅ **ジオフェンス機能には「常に許可」が必須**
- ❌ 「使用中のみ許可」では、バックグラウンドでジオフェンス検知できない
- 📱 設定方法: 設定 → プライバシー → 位置情報サービス → LocationReminder → **「常に」を選択**

### バックグラウンド動作

- iOS 17+: CLBackgroundActivitySession 使用
- iOS 16 以下: BGTaskScheduler 使用
- 電力消費を抑えるため、自宅内のみ頻繁な監視を実行
- **BGTask スケジュール間隔**: 指数バックオフ方式（1 分 →2 分 →4 分 →...→ 最大 60 分）
- **持続時間**: iOS の制限により、バックグラウンドタスクは数分間のみ実行可能
- **最大間隔**: 60 分まで延長可能（帰宅直後は 1 分から開始）
- **推奨**: 長期間の UWB 接続を維持するには、定期的にアプリを開くか、自宅に戻る度に自動再接続を利用

### Screen Time 制限

- FamilyControls 認証が必要
- 制限対象アプリを選択していない場合は制限されない
- UWB 接続がない場合は制限されない

---

## 🔧 トラブルシューティング

### ジオフェンスが動作しない場合

#### 1. 位置情報の許可を確認

```
設定 → プライバシー → 位置情報サービス → LocationReminder
```

- ✅ 「常に」が選択されているか確認
- ❌ 「使用中のみ」または「なし」の場合は動作しません

#### 2. ジオフェンシング設定画面で状態を確認

アプリ内の「ジオフェンシング設定」画面で以下を確認：

| 項目             | 期待される状態 | 対処法                                 |
| ---------------- | -------------- | -------------------------------------- |
| 位置情報許可     | 常に許可       | 設定アプリで「常に」を選択             |
| ジオフェンス監視 | 有効           | 自宅位置を再設定                       |
| 在宅状態         | 自宅内/不在    | Xcode のコンソールログで状態判定を確認 |

#### 3. Xcode のコンソールログを確認

アプリ実行中のログで以下を確認：

```
✅ 位置情報サービスの設定完了
📍 現在の位置情報許可状態: 常に許可
🔧 setupGeofencing 呼び出し
   自宅位置設定: ✅
   位置情報許可: 常に許可
✅ ジオフェンス監視開始: home
🔍 ジオフェンス状態判定: home - 内部/外部
```

#### 4. ジオフェンス進入/退出がトリガーされない

- ジオフェンスの検知には**数十メートル以上の移動**が必要です
- 50m 程度の移動では検知されない場合があります（iOS の仕様）
- **推奨テスト方法**: 200m 以上離れてから戻る
- デバッグ通知をオンにして、実際に通知が届くか確認

#### 5. 在宅状態が更新されない

- アプリを完全に再起動（スワイプで終了 → 再起動）
- 自宅位置を再設定して、ジオフェンスを再初期化
- 設定アプリで位置情報許可を「なし」→「常に」と再設定

---

## 🚀 今後の改善案

1. ✅ ~~UWB 接続時の位置情報監視停止（完了）~~
2. ✅ ~~バックグラウンドタスク間隔の延長（完了）~~
3. ✅ ~~自動再接続の改善（完了）~~
4. ✨ ジオフェンス半径の動的調整機能
5. ✨ 複数の自宅・職場位置対応
6. ✨ 位置ごとの異なる Screen Time 設定
7. ✨ ジオフェンス進入/退出の履歴表示
8. ✨ 統計データの可視化強化

---

## 📚 参考資料

- [Core Location - Apple Developer](https://developer.apple.com/documentation/corelocation)
- [Nearby Interaction - Apple Developer](https://developer.apple.com/documentation/nearbyinteraction)
- [Screen Time API - Apple Developer](https://developer.apple.com/documentation/familycontrols)

---

**作成日**: 2025-10-11  
**最終更新**: 2025-10-12  
**バージョン**: 1.3.0

## 📝 更新履歴

### v1.3.0 (2025-10-12)

- 🔔 **UWB ペアリングデバッグ通知**: 接続開始・成功・失敗時に通知を表示
- 📱 **詳細な接続状態追跡**: Bluetooth 接続から NI セッションまで各段階を通知
- 🎛️ **トグル追加**: UWBSettingsView でデバッグ通知のオン/オフが可能

### v1.2.0 (2025-10-12)

- 📊 **指数バックオフ方式**: BG タスクの間隔を動的に調整（1 分 →2 分 →4 分 →...→ 最大 60 分）
- 🔄 **スマートリセット**: ジオフェンス進入時・UWB 切断時に間隔を 1 分にリセット
- 🔋 **バッテリー最適化**: 帰宅直後は頻繁に試み、時間経過で間隔を延長

### v1.1.0 (2025-10-12)

- 🔧 **自動再接続の改善**: ジオフェンス進入時に必ず UWB 接続を試みるように変更
- ⏱️ **バックグラウンドタスク間隔延長**: 固定 15 分 → 指数バックオフ方式に変更
- 📍 **位置情報監視の最適化**: UWB 接続時にジオフェンス監視を一時停止、切断時に自動再開
- 👁️ **UI 改善**: GeofencingSettingsView に位置情報監視状態を表示

### v1.0.0 (2025-10-11)

- 初版リリース
