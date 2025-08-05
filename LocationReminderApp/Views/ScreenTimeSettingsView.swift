import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity
import UIKit

// FamilyActivitySelectionを永続化するためのヘルパー
class FamilyActivitySelectionStore: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    
    private let userDefaults = UserDefaults.standard
    private let applicationsKey = "FamilyActivitySelectionApplications"
    private let categoriesKey = "FamilyActivitySelectionCategories"
    private let webDomainsKey = "FamilyActivitySelectionWebDomains"

    init() {
        loadSelection()
    }
    
    func saveSelection() {
        do {
            // 各トークンセットが空でない場合のみエンコード
            let applicationsData = selection.applicationTokens.isEmpty ? nil : try? JSONEncoder().encode(selection.applicationTokens)
            let categoriesData = selection.categoryTokens.isEmpty ? nil : try? JSONEncoder().encode(selection.categoryTokens)
            let webDomainsData = selection.webDomainTokens.isEmpty ? nil : try? JSONEncoder().encode(selection.webDomainTokens)
            
            // データが存在する場合のみ保存、空の場合は削除
            if let applicationsData = applicationsData {
                userDefaults.set(applicationsData, forKey: applicationsKey)
            } else {
                userDefaults.removeObject(forKey: applicationsKey)
            }
            
            if let categoriesData = categoriesData {
                userDefaults.set(categoriesData, forKey: categoriesKey)
            } else {
                userDefaults.removeObject(forKey: categoriesKey)
            }
            
            if let webDomainsData = webDomainsData {
                userDefaults.set(webDomainsData, forKey: webDomainsKey)
            } else {
                userDefaults.removeObject(forKey: webDomainsKey)
            }

            print("\n=== 🔒 FamilyActivitySelection 保存処理 ===")
            print("✅ 保存完了")
            print("📱 アプリ数: \(selection.applicationTokens.count)")
            print("📂 カテゴリ数: \(selection.categoryTokens.count)")
            print("🌐 Webドメイン数: \(selection.webDomainTokens.count)")
            print("============================================\n")
        } catch {
            print("\n❌ FamilyActivitySelection保存エラー: \(error)\n")
        }
    }
    
    func loadSelection() {
        var loadedSelection = FamilyActivitySelection()
        
        do {
            if let applicationsData = userDefaults.data(forKey: applicationsKey) {
                loadedSelection.applicationTokens = try JSONDecoder().decode(Set<ApplicationToken>.self, from: applicationsData)
            }
            if let categoriesData = userDefaults.data(forKey: categoriesKey) {
                loadedSelection.categoryTokens = try JSONDecoder().decode(Set<ActivityCategoryToken>.self, from: categoriesData)
            }
            if let webDomainsData = userDefaults.data(forKey: webDomainsKey) {
                loadedSelection.webDomainTokens = try JSONDecoder().decode(Set<WebDomainToken>.self, from: webDomainsData)
            }
            
            self.selection = loadedSelection
            print("\n=== 📥 FamilyActivitySelection 読み込み処理 ===")
            print("✅ 読み込み完了")
            print("📱 アプリ数: \(selection.applicationTokens.count)")
            print("📂 カテゴリ数: \(selection.categoryTokens.count)")
            print("🌐 Webドメイン数: \(selection.webDomainTokens.count)")
            print("=============================================\n")
        } catch {
            print("\n❌ FamilyActivitySelection読み込みエラー: \(error)\n")
        }
    }
    
    func clearSelection() {
        selection = FamilyActivitySelection()
        userDefaults.removeObject(forKey: applicationsKey)
        userDefaults.removeObject(forKey: categoriesKey)
        userDefaults.removeObject(forKey: webDomainsKey)
        print("\n=== 🗑️ FamilyActivitySelection クリア処理 ===")
        print("✅ クリア完了")
        print("============================================\n")
    }
}

// Screen Time管理クラス（実際の実装）
class ScreenTimeManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var isRestrictionEnabled = false
    @Published var isUWBLinked = true
    @Published var authorizationStatus = "未認証"
    
    private let authorizationCenter = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()
    
    // FamilyActivitySelectionStoreを使用
    @Published var activitySelectionStore = FamilyActivitySelectionStore()
    
    init() {
        checkAuthorizationStatus()
        setupShieldActionNotifications()
        
        // 初回起動時に自動的に認証ダイアログを表示
        if authorizationCenter.authorizationStatus == .notDetermined {
            requestAuthorization()
        }
    }
    
    // 認証状態を確認
    private func checkAuthorizationStatus() {
        print("\n=== 🔐 Screen Time 認証状態確認 ===")
        switch authorizationCenter.authorizationStatus {
        case .approved:
            isAuthorized = true
            authorizationStatus = "認証済み"
            print("✅ 認証状態: 認証済み")
        case .denied:
            isAuthorized = false
            authorizationStatus = "認証拒否"
            print("❌ 認証状態: 認証拒否")
        case .notDetermined:
            isAuthorized = false
            authorizationStatus = "未認証"
            print("⚠️ 認証状態: 未認証")
        @unknown default:
            isAuthorized = false
            authorizationStatus = "不明"
            print("❓ 認証状態: 不明")
        }
        print("🎯 制限状態: \(isRestrictionEnabled ? "有効" : "無効")")
        print("🔗 UWB連動: \(isUWBLinked ? "有効" : "無効")")
        print("=====================================\n")
    }
    
    // 認証をリクエスト
    func requestAuthorization() {
        print("\n=== 🔑 Screen Time 認証リクエスト ===")
        Task {
            do {
                try await authorizationCenter.requestAuthorization(for: .individual)
                await MainActor.run {
                    print("✅ 認証リクエスト完了")
                    checkAuthorizationStatus()
                }
            } catch {
                print("❌ 認証エラー: \(error)")
                await MainActor.run {
                    authorizationStatus = "認証エラー"
                }
            }
        }
        print("==================================\n")
    }
    
    // 手動で制限を切り替え
    func toggleRestriction() {
        if isRestrictionEnabled {
            disableRestriction()
        } else {
            enableRestriction()
        }
    }
    
    // 制限を有効化（カテゴリ選択の問題を修正）
    private func enableRestriction() {
        guard isAuthorized else { 
            print("\n❌ Screen Time制限有効化失敗: 認証されていません\n")
            return 
        }
        
        print("\n=== 🛡️ Screen Time制限 有効化処理 ===")
        
        let selection = activitySelectionStore.selection
        let hasAppsSelected = !selection.applicationTokens.isEmpty
        let hasCategoriesSelected = !selection.categoryTokens.isEmpty
        let hasWebDomainsSelected = !selection.webDomainTokens.isEmpty
        
        print("📱 選択されたアプリ数: \(selection.applicationTokens.count)")
        print("📂 選択されたカテゴリ数: \(selection.categoryTokens.count)")
        print("🌐 選択されたWebドメイン数: \(selection.webDomainTokens.count)")
        
        guard hasAppsSelected || hasCategoriesSelected || hasWebDomainsSelected else {
            print("⚠️ 制限対象が選択されていません")
            // 選択がない場合、もし有効なら無効化する
            if isRestrictionEnabled {
                disableRestriction()
            }
            print("=====================================\n")
            return
        }
        
        // 既存の設定をクリアしてから適用
        store.clearAllSettings()
        print("🧹 既存設定をクリア")
        
        // アプリの制限を設定
        if hasAppsSelected {
            store.shield.applications = selection.applicationTokens
            print("📱 アプリ制限を設定")
        }
        
        // カテゴリの制限を設定
        if hasCategoriesSelected {
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
                selection.categoryTokens,
                except: Set<ApplicationToken>()
            )
            print("📂 カテゴリ制限を設定")
        }
        
        // Webドメインの制限を設定
        if hasWebDomainsSelected {
            store.shield.webDomains = selection.webDomainTokens
            print("🌐 Webドメイン制限を設定")
            
            // 選択したWebドメインのみをブロック（.all()を削除）
            // store.webContent.blockedByFilter = .all() // この行を削除して選択したドメインのみ制限
            print("🚫 選択されたWebドメインのみ制限を適用")
        }
        
        DispatchQueue.main.async {
            self.isRestrictionEnabled = true
            print("✅ Screen Time制限を有効化しました")
            print("=====================================\n")
        }
    }
    
    // 制限を無効化
    private func disableRestriction() {
        print("\n=== 🔓 Screen Time制限 無効化処理 ===")
        
        // すべての制限を解除
        store.clearAllSettings()
        print("🧹 すべての制限設定をクリア")
        
        DispatchQueue.main.async {
            self.isRestrictionEnabled = false
            print("✅ Screen Time制限を無効化しました")
            print("=====================================\n")
        }
    }
    
    // Secure Bubble内での自動制限有効化
    func enableRestrictionForSecureBubble() {
        guard isUWBLinked else { return }
        print("\n🔵 UWB Secure Bubble内 - 制限有効化")
        enableRestriction()
    }
    
    // Secure Bubble外での自動制限無効化
    func disableRestrictionForSecureBubble() {
        guard isUWBLinked else { return }
        print("\n🔴 UWB Secure Bubble外 - 制限無効化")
        disableRestriction()
    }
    
    // 選択されたアプリの数を取得
    var selectedAppsCount: Int {
        return activitySelectionStore.selection.applicationTokens.count
    }
    
    // 選択されたアプリを全て削除
    func clearSelectedApps() {
        activitySelectionStore.clearSelection()
    }
    
    // 選択状態の詳細情報
    var selectionDetails: String {
        let appsCount = activitySelectionStore.selection.applicationTokens.count
        let categoriesCount = activitySelectionStore.selection.categoryTokens.count
        let webDomainsCount = activitySelectionStore.selection.webDomainTokens.count
        
        var details: [String] = []
        if appsCount > 0 { details.append("アプリ: \(appsCount)個") }
        if categoriesCount > 0 { details.append("カテゴリ: \(categoriesCount)個") }
        if webDomainsCount > 0 { details.append("Webドメイン: \(webDomainsCount)個") }
        
        return details.isEmpty ? "未選択" : details.joined(separator: ", ")
    }
    
    // ShieldActionExtensionからの通知を設定
    private func setupShieldActionNotifications() {
        print("\n=== 🛡️ Shield Action通知設定 ===")
        print("✅ 通知監視を開始")
        print("================================\n")
        
        // App Groupsを使用した定期的なポーリング
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.checkForShieldActions()
        }
    }
    
    private func checkForShieldActions() {
        // App Groupsから未処理のアクションを確認
        let defaults = UserDefaults(suiteName: "group.com.locationreminder.shieldaction")
        guard defaults?.string(forKey: "pendingAction") != nil else { return }
        
        // 処理済みのアクションでないことを確認
        if let lastCheck = defaults?.object(forKey: "lastProcessedTimestamp") as? Date,
           let actionTimestamp = defaults?.object(forKey: "actionTimestamp") as? Date,
           actionTimestamp <= lastCheck {
            return
        }
        
        // アクションを処理
        handleShieldAction()
        
        // 処理済みとしてマーク
        defaults?.set(Date(), forKey: "lastProcessedTimestamp")
    }
    
    // ShieldActionExtensionからの通知を処理
    private func handleShieldAction() {
        DispatchQueue.main.async {
            print("\n=== 🛡️ Shield Action処理 ===")
            
            // App Groupsからアクション情報を取得
            let defaults = UserDefaults(suiteName: "group.com.locationreminder.shieldaction")
            guard let action = defaults?.string(forKey: "pendingAction") else { return }
            
            print("📢 受信したアクション: \(action)")
            
            // アクションを実行
            switch action {
            case "openSettings":
                self.openSettings()
                print("⚙️ 設定画面を開きました")
            default:
                print("❓ 未知のアクション: \(action)")
                break
            }
            
            // 処理済みのアクションを削除
            defaults?.removeObject(forKey: "pendingAction")
            defaults?.removeObject(forKey: "actionTimestamp")
            print("🗑️ 処理済みアクションを削除")
            print("============================\n")
        }
    }
    
    // 設定アプリを開く
    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
        }
    }
    
    // デイニシャライザでリソースをクリーンアップ
    deinit {
        print("\n=== 🔄 ScreenTimeManager デイニシャライザ ===")
        print("♻️ リソースをクリーンアップしました")
        print("==========================================\n")
    }
}

struct ScreenTimeSettingsView: View {
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingAppSelection = false
    @State private var showingPermissionAlert = false
    @State private var isPickerReady = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            // UWB連動設定
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "wave.3.right.circle.fill")
                            .foregroundColor(screenTimeManager.isUWBLinked ? .blue : .gray)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UWB Secure Bubble連動")
                                .font(.headline)
                            Text(screenTimeManager.isUWBLinked ? "有効" : "無効")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $screenTimeManager.isUWBLinked)
                    }
                    
                    if screenTimeManager.isUWBLinked {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("現在の状態:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack {
                                Circle()
                                    .fill(uwbManager.isInSecureBubble ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text(uwbManager.isInSecureBubble ? "Secure Bubble内 - 制限有効" : "Secure Bubble外 - 制限無効")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let distance = uwbManager.currentDistance {
                                HStack {
                                    Image(systemName: "location.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    Text(String(format: "距離: %.2fm", distance))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("UWB連動設定")
            } footer: {
                Text("有効にすると、Secure Bubble内にいる時に自動的にアプリ制限が適用されます。")
            }
            
            // アプリ選択
            Section {
                                 Button(action: {
                     if screenTimeManager.isAuthorized {
                         print("\n=== 📱 FamilyActivityPicker 表示 ===")
                         print("🔓 認証済み - アプリ選択画面を表示します")
                         
                         // pickerの表示を少し遅延させる（FamilyControlsフレームワークの準備時間を確保）
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                             isPickerReady = true
                             showingAppSelection = true
                         }
                     } else {
                         print("\n❌ FamilyActivityPicker表示失敗: 認証が必要です")
                         showingPermissionAlert = true
                     }
                     print("=====================================\n")
                 }) {
                    HStack {
                        Image(systemName: "apps.iphone")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("制限するアプリを選択")
                                .foregroundColor(.primary)
                                .font(.headline)
                            
                            Text(screenTimeManager.selectionDetails)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!screenTimeManager.isAuthorized)
                
                // 選択されたアプリをクリア
                if screenTimeManager.selectedAppsCount > 0 {
                    Button("選択したアプリをクリア") {
                        screenTimeManager.clearSelectedApps()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            } header: {
                Text("制限対象アプリ")
            } footer: {
                Text("FamilyActivityPickerを使用してシステムのアプリ選択画面を表示します。")
            }
        }
        .navigationTitle("Screen Time設定")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(
            isPresented: Binding(
                get: { showingAppSelection && isPickerReady && screenTimeManager.isAuthorized },
                set: { newValue in 
                    showingAppSelection = newValue
                    if !newValue {
                        isPickerReady = false
                    }
                }
            ),
            selection: $screenTimeManager.activitySelectionStore.selection
        )
        .onChange(of: screenTimeManager.activitySelectionStore.selection) { newValue in
            print("\n=== 📝 アプリ選択変更 ===")
            print("📱 アプリ数: \(newValue.applicationTokens.count)")
            print("📂 カテゴリ数: \(newValue.categoryTokens.count)")
            print("🌐 Webドメイン数: \(newValue.webDomainTokens.count)")
            
            // 選択を永続化
            screenTimeManager.activitySelectionStore.saveSelection()
            
            // UWB連動が有効でSecure Bubble内にいる場合、即座に制限を適用
            if screenTimeManager.isUWBLinked && uwbManager.isInSecureBubble {
                print("🔄 Secure Bubble内のため、即座に制限を更新")
                screenTimeManager.enableRestrictionForSecureBubble()
            } else if screenTimeManager.isUWBLinked && !uwbManager.isInSecureBubble {
                print("🔄 Secure Bubble外のため、制限を無効化")
                screenTimeManager.disableRestrictionForSecureBubble()
            }
            print("=======================\n")
        }
        .onChange(of: showingAppSelection) { newValue in
            if newValue {
                print("\n=== 📱 FamilyActivityPicker 表示開始 ===")
            } else {
                print("\n=== 📱 FamilyActivityPicker 表示終了 ===")
                isPickerReady = false  // 閉じた時にリセット
            }
            print("========================================\n")
        }
        .alert("認証が必要です", isPresented: $showingPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("アプリ選択機能を使用するには、Family Controlsの認証が必要です。")
        }
    }
}

#Preview {
    NavigationView {
        ScreenTimeSettingsView()
            .environmentObject(ScreenTimeManager())
    }
} 
