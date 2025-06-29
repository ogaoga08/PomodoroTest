# Screen Time API と UWB 連動機能 実装ガイド

## 概要

本ドキュメントでは、UWB 通信の Secure Bubble 機能と Apple の Screen Time API を連動させて、作業スペース内でのアプリ使用制限機能を実装する方法について説明します。

## 必要な要件

### Apple Developer Program

- **Family Controls API**: 特別な申請と承認が必要
- **ManagedSettings Framework**: iOS 15.0+
- **DeviceActivity Framework**: 使用状況監視用
- **FamilyControls Framework**: 認証と UI 提供

### 申請プロセス

1. Apple Developer Program に登録
2. [Family Controls Distribution Request](https://developer.apple.com/contact/request/family-controls-distribution) で申請
3. アプリの具体的な用途と必要性を説明
4. 通常は保護者制御アプリや組織管理アプリのみ承認

## 実装プロセス

### 1. プロジェクト設定

#### Capabilities 追加

```xml
<!-- Info.plist -->
<key>NSFamilyControlsUsageDescription</key>
<string>この機能により、作業時間中の集中力向上のためアプリ使用を制限します</string>
```

#### Framework 追加

```swift
import FamilyControls
import ManagedSettings
import DeviceActivity
```

### 2. 認証実装

```swift
import FamilyControls

class ScreenTimeManager: ObservableObject {
    @Published var isAuthorized = false

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await MainActor.run {
                self.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            }
        } catch {
            print("認証エラー: \(error)")
        }
    }
}
```

### 3. アプリ選択 UI 実装

```swift
import FamilyControls

struct AppSelectionView: View {
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        FamilyActivityPicker(selection: $selection)
            .onChange(of: selection) { newSelection in
                // 選択されたアプリを保存
                saveSelectedApps(newSelection)
            }
    }

    private func saveSelectedApps(_ selection: FamilyActivitySelection) {
        // ManagedSettingsに設定を保存
        let store = ManagedSettingsStore()
        store.application.blockedApplications = selection.applicationTokens
        store.shield.applications = selection.applicationTokens
    }
}
```

### 4. アプリ制限実装

```swift
import ManagedSettings

class RestrictionManager {
    private let store = ManagedSettingsStore()

    func enableRestrictions(for apps: Set<ApplicationToken>) {
        // アプリケーション制限を有効化
        store.application.blockedApplications = apps

        // シールド設定（制限時の表示）
        store.shield.applications = apps
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            Set<ActivityCategoryToken>(),
            except: Set<ApplicationToken>()
        )
    }

    func disableRestrictions() {
        // 全ての制限を解除
        store.clearAllSettings()
    }
}
```

### 5. UWB 連動実装

```swift
// UWBManager.swift への追加実装

extension UWBManager {
    private var restrictionManager = RestrictionManager()

    private func handleSecureBubbleChange(isInside: Bool) {
        guard let screenTimeManager = screenTimeManager else { return }

        if screenTimeManager.isUWBLinked && screenTimeManager.isAuthorized {
            if isInside {
                // Secure Bubble内では制限を有効化
                restrictionManager.enableRestrictions(for: screenTimeManager.selectedAppTokens)
                notifyRestrictionChange(enabled: true)
            } else {
                // Secure Bubble外では制限を解除
                restrictionManager.disableRestrictions()
                notifyRestrictionChange(enabled: false)
            }
        }
    }

    private func notifyRestrictionChange(enabled: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "アプリ制限"
        content.body = enabled ? "作業スペースに入りました。アプリ制限が有効になります。" : "作業スペースから離れました。アプリ制限が解除されます。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "restriction_change_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

### 6. 詳細設定画面

```swift
struct AdvancedScreenTimeSettingsView: View {
    @StateObject private var manager = ScreenTimeManager()
    @State private var activitySelection = FamilyActivitySelection()

    var body: some View {
        List {
            // 認証セクション
            Section("認証") {
                Button("Family Controls認証") {
                    Task {
                        await manager.requestAuthorization()
                    }
                }
                .disabled(manager.isAuthorized)
            }

            // アプリ選択セクション
            Section("制限対象アプリ") {
                FamilyActivityPicker(selection: $activitySelection)
                    .disabled(!manager.isAuthorized)
            }

            // UWB連動設定
            Section("UWB連動") {
                Toggle("Secure Bubble連動", isOn: $manager.isUWBLinked)
                    .disabled(!manager.isAuthorized)
            }
        }
    }
}
```

## セキュリティと注意事項

### プライバシー配慮

- **最小権限の原則**: 必要最小限のアプリのみ制限対象とする
- **透明性**: ユーザーに制限内容を明確に説明
- **制御権**: ユーザーがいつでも制限を解除できる仕組み

### 技術的制約

- **デバイス要件**: iOS 15.0 以上、UWB 対応デバイス
- **ネットワーク**: オフライン動作を想定した設計
- **バッテリー**: UWB 通信による消費電力への配慮

### App Store 審査対策

- **明確な用途説明**: Family Controls API 使用の正当性を説明
- **ユーザー同意**: 明示的な許可取得プロセス
- **代替手段**: API 無効時の代替機能提供

## 現在の実装状況

### 完成済み機能

- ✅ MenuView に Screen Time 設定項目追加
- ✅ ScreenTimeSettingsView（プレビュー版）作成
- ✅ UWBManager 連動ロジック実装
- ✅ モックアプリ選択 UI

### 本格実装時の追加作業

- 🔄 Family Controls API 認証申請
- 🔄 FamilyActivityPicker 統合
- 🔄 ManagedSettingsStore 実装
- 🔄 DeviceActivity 監視機能
- 🔄 ShieldConfiguration 設定

## 参考資料

- [Apple Developer - Family Controls](https://developer.apple.com/documentation/familycontrols)
- [Managing App and Website Restrictions](https://developer.apple.com/documentation/familycontrols/managing_app_and_website_restrictions)
- [Nearby Interaction Framework](https://developer.apple.com/documentation/nearbyinteraction)
- [WWDC 2023 - Meet App Store privacy requirements](https://developer.apple.com/videos/play/wwdc2023/10060/)

## トラブルシューティング

### よくある問題

1. **認証失敗**: Apple Developer Program の有効性確認
2. **API 制限**: Family Controls 承認状況の確認
3. **UWB 接続**: デバイス対応状況と Bluetooth 設定確認
4. **制限無効**: ManagedSettingsStore の設定内容確認

### デバッグ方法

```swift
// 認証状態確認
print("Family Controls認証状態: \(AuthorizationCenter.shared.authorizationStatus)")

// 制限設定確認
let store = ManagedSettingsStore()
print("制限中アプリ数: \(store.application.blockedApplications?.count ?? 0)")

// UWB状態確認
print("Secure Bubble状態: \(UWBManager.shared.isInSecureBubble)")
```
