# バックグラウンド自動再接続の仕組み

## 📱 UIBackgroundModes の説明

`Info.plist`に設定されている`UIBackgroundModes`により、バックグラウンドでの継続実行が可能になります：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>  ★ 最重要
    <string>nearby-interaction</string>  ★ 最重要
    <string>processing</string>         (BGTaskScheduler用・補助的)
    <string>fetch</string>              (バックグラウンドフェッチ用・補助的)
</array>
```

**注**: `location`は不要（位置情報は使用しない）

### 🔑 重要な 2 つのモード

#### 1. `bluetooth-central`

- **Bluetooth 接続がバックグラウンドで無期限に維持される**
- Bluetooth 通信イベント（データ送受信）により、アプリが起動される
- `CBCentralManagerDelegate`のメソッドがバックグラウンドでも呼ばれる
- **30 秒制限を超えて実行可能**

#### 2. `nearby-interaction`

- **NISession がバックグラウンドで継続実行される**
- `NISessionDelegate`のメソッドがバックグラウンドでも呼ばれる
- デバイスに近づいた時、**自動的に`session(_:didUpdate:)`が呼ばれる**
- **ユーザーが何もしなくても距離データが更新される**

## 🔄 バックグラウンド自動再接続の動作フロー

### **ケース 1: デバイスから離れる（範囲外）**

```
1. 距離が10m以上離れる
   ↓
2. session(_:didRemove:) が呼ばれる（reason: .timeout or .peerEnded）
   ↓
3. retryDistanceMeasurement() 実行
   - stop → initialize メッセージ送信（Qorvoパターン）
   ↓
4. NISessionは維持される（invalidateしない）
   Bluetooth接続も維持される
   ↓
5. デバイスが範囲外のため距離データなし
   → device.distance = nil（正常）
```

### **ケース 2: デバイスに近づく（バックグラウンドのまま）**

```
1. ユーザーがUWBデバイスに近づく（範囲内）
   ↓
2. 🔑 重要: nearby-interactionモードにより
   session(_:didUpdate:) が自動的に呼ばれる
   ↓
3. 距離データが更新される
   device.distance = X.XXm
   device.status = .ranging
   ↓
4. 📱 通知: "🎯 距離計測自動復旧"
   ↓
5. ✅ ユーザーは何もしなくても自動復旧
```

### **ケース 3: フォアグラウンド復帰時**

```
1. アプリを開く
   ↓
2. appWillEnterForeground() → checkAndRestoreNISessionsOnForeground()
   ↓
3. 状態チェック:
   - NISession: 有り
   - Bluetooth: 接続中
   - 距離データ: なし
   ↓
4. initialize メッセージを強制送信
   ↓
5. デバイスが範囲内 → 距離データ取得
   デバイスが範囲外 → 距離データなし（正常）
```

## ⚙️ 実装の核心部分

### 1. **didRemove 時の処理（Qorvo パターン）**

```swift
func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
    switch reason {
    case .timeout, .peerEnded:
        // 🔑 Qorvoパターン: stop → initialize
        retryDistanceMeasurement(for: device)
    }
}

private func retryDistanceMeasurement(for device: UWBDevice) {
    // 1. stop送信
    sendDataToDevice(Data([MessageId.stop.rawValue]), device: device)

    // 2. 0.5秒後にinitialize送信
    // bluetooth-centralモードにより、Bluetooth通信で実行時間が延長される
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        sendDataToDevice(Data([MessageId.initialize.rawValue]), device: device)
    }

    // 3. NISessionは維持される（invalidateしない）
    // 4. デバイスに近づけば、session(_:didUpdate:)が自動的に呼ばれる
}
```

### 2. **didUpdate 時の処理（バックグラウンド検出）**

```swift
func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
    let isFirstDistance = device.distance == nil

    if isFirstDistance {
        if isBackgroundMode {
            // 🎯 バックグラウンドで距離データ復旧を検出
            logger.info("🎯✨ バックグラウンドで距離データ復旧")
            logger.info("✅ bluetooth-central + nearby-interactionモードにより自動復旧成功")

            // 通知送信
            sendUWBPairingDebugNotification(
                title: "🎯 距離計測自動復旧",
                message: "バックグラウンドで距離: X.XXm"
            )
        }
    }

    // 距離データを更新
    device.distance = distance
    device.status = .ranging
}
```

### 3. **フォアグラウンド復帰時の処理**

```swift
private func checkAndRestoreNISessionsOnForeground() {
    // NISessionはあるが距離データがない場合
    if hasNISession && hasConfiguration && device.distance == nil {
        // Qorvoパターン: initializeメッセージを送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            sendDataToDevice(Data([MessageId.initialize.rawValue]), device: device)
        }
    }
}
```

## 🔑 なぜ BGTaskScheduler は不要か

### ❌ BGTaskScheduler の問題点

- 実行タイミングが不確実（システムの裁量）
- 最短でも 15 分間隔
- 充電中や特定条件下でしか実行されない
- バッテリーやネットワーク状態により実行されないことがある

### ✅ bluetooth-central + nearby-interaction モードの利点

- **確実に動作**（システムが保証）
- Bluetooth 接続と NISession が自動的に維持される
- デリゲートメソッドがバックグラウンドでも呼ばれる
- デバイスに近づいた瞬間に`session(_:didUpdate:)`が呼ばれる
- **ユーザーが何もしなくても自動復旧**

## 📊 バックグラウンド実行の持続時間

### UIApplication.beginBackgroundTask

- ⏱️ 最大約 30 秒
- アプリがバックグラウンドに移行した直後の短期的なタスク用

### bluetooth-central + nearby-interaction モード

- ⏱️ **無期限**（Bluetooth 接続と NISession が維持される限り）
- Bluetooth 通信イベントによりアプリが定期的に起動される
- NISession のイベント（距離更新）により起動される

## ⚠️ 重要な注意点

### NISession を維持する

- 距離が離れても**invalidate しない**
- `didRemove`時は`retryDistanceMeasurement`を呼ぶだけ
- NISession が維持されていれば、デバイスに近づいた時に自動的に`didUpdate`が呼ばれる

### 複雑な再ペアリングロジックは不要

- 10 回の試行制限、指数バックオフ、クールダウン期間などは不要
- Qorvo サンプルコードのシンプルなパターンで十分
- `stop` → `initialize`メッセージを送信するだけ

### BGTaskScheduler は補助的

- 15 分〜60 分間隔で定期チェック
- NISession が何らかの理由で喪失した場合の最終的なバックアップ
- 主な復旧手段ではない

## 🎯 期待される動作

### **ユーザー体験**

1. **部屋を離れる（バックグラウンド）**

   - 距離が遠くなる → 距離データが消える
   - NISession と Bluetooth 接続は維持される

2. **長時間離れている**

   - アプリはバックグラウンドで継続実行
   - bluetooth-central モードにより接続維持
   - バッテリー消費は最小限

3. **部屋に戻る（バックグラウンドのまま）**

   - デバイスに近づく
   - **自動的に`session(_:didUpdate:)`が呼ばれる**
   - 距離データが復旧
   - 📱 通知: "🎯 距離計測自動復旧"

4. **アプリを開く**
   - 既に距離データが復旧している（何もしなくて良い）
   - または、距離データがない場合は強制的に`initialize`送信

## 🔧 テスト方法

### UWB ペアリングデバッグ通知を有効化

UWB 設定画面で「UWB ペアリング通知」を ON にすると、以下の通知が表示されます：

1. **デバイスから離れた時**

   - "🔄 距離計測再初期化"

2. **デバイスに近づいた時（バックグラウンド）**

   - "🎯 距離計測自動復旧"
   - "バックグラウンドで距離: X.XXm"

3. **NISession 無効化時**
   - "⚠️ UWB セッション切断"
   - その後、自動的に再作成される

これらの通知により、バックグラウンドでの自動復旧が正しく動作しているか確認できます。
