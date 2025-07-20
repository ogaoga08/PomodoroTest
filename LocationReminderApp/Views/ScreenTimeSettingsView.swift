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
            let applicationsData = try? JSONEncoder().encode(selection.applicationTokens)
            let categoriesData = try? JSONEncoder().encode(selection.categoryTokens)
            let webDomainsData = try? JSONEncoder().encode(selection.webDomainTokens)
            
            userDefaults.set(applicationsData, forKey: applicationsKey)
            userDefaults.set(categoriesData, forKey: categoriesKey)
            userDefaults.set(webDomainsData, forKey: webDomainsKey)

            print("FamilyActivitySelection保存完了")
            print("- アプリ数: \(selection.applicationTokens.count)")
            print("- カテゴリ数: \(selection.categoryTokens.count)")
            print("- Webドメイン数: \(selection.webDomainTokens.count)")
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
            print("FamilyActivitySelection読み込み完了")
            print("- アプリ数: \(selection.applicationTokens.count)")
            print("- カテゴリ数: \(selection.categoryTokens.count)")
            print("- Webドメイン数: \(selection.webDomainTokens.count)")
        } catch {
            print("FamilyActivitySelection読み込みエラー: \(error)")
        }
    }
    
    func clearSelection() {
        selection = FamilyActivitySelection()
        userDefaults.removeObject(forKey: applicationsKey)
        userDefaults.removeObject(forKey: categoriesKey)
        userDefaults.removeObject(forKey: webDomainsKey)
        print("FamilyActivitySelectionをクリアしました")
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
        logDebugInfo()
        
        // 初回起動時に自動的に認証ダイアログを表示
        if authorizationCenter.authorizationStatus == .notDetermined {
            requestAuthorization()
        }
    }
    
    // デバッグ情報をログに出力
    private func logDebugInfo() {
        print("=== Screen Time Debug Info ===")
        print("認証状態: \(authorizationStatus)")
        print("制限状態: \(isRestrictionEnabled ? "有効" : "無効")")
        print("UWB連動: \(isUWBLinked ? "有効" : "無効")")
        print("選択されたアプリ数: \(activitySelectionStore.selection.applicationTokens.count)")
        print("選択されたカテゴリ数: \(activitySelectionStore.selection.categoryTokens.count)")
        print("選択されたWebドメイン数: \(activitySelectionStore.selection.webDomainTokens.count)")
        print("================================")
    }
    
    // 認証状態を確認
    private func checkAuthorizationStatus() {
        switch authorizationCenter.authorizationStatus {
        case .approved:
            isAuthorized = true
            authorizationStatus = "認証済み"
        case .denied:
            isAuthorized = false
            authorizationStatus = "認証拒否"
        case .notDetermined:
            isAuthorized = false
            authorizationStatus = "未認証"
        @unknown default:
            isAuthorized = false
            authorizationStatus = "不明"
        }
        logDebugInfo()
    }
    
    // 認証をリクエスト
    func requestAuthorization() {
        Task {
            do {
                try await authorizationCenter.requestAuthorization(for: .individual)
                await MainActor.run {
                    checkAuthorizationStatus()
                }
            } catch {
                print("認証エラー: \(error)")
                await MainActor.run {
                    authorizationStatus = "認証エラー"
                }
            }
        }
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
        guard isAuthorized else { return }
        
        let selection = activitySelectionStore.selection
        let hasAppsSelected = !selection.applicationTokens.isEmpty
        let hasCategoriesSelected = !selection.categoryTokens.isEmpty
        let hasWebDomainsSelected = !selection.webDomainTokens.isEmpty
        
        guard hasAppsSelected || hasCategoriesSelected || hasWebDomainsSelected else {
            print("制限対象が選択されていません")
            // 選択がない場合、もし有効なら無効化する
            if isRestrictionEnabled {
                disableRestriction()
            }
            return
        }
        
        // 既存の設定をクリアしてから適用
        store.clearAllSettings()
        
        // アプリの制限を設定
        store.shield.applications = selection.applicationTokens
        
        // カテゴリの制限を設定
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
                selection.categoryTokens,
                except: Set<ApplicationToken>()
            )
        }
        
        // Webドメインの制限を設定
        store.shield.webDomains = selection.webDomainTokens
        
        // Webコンテンツもブロックしたい場合
        store.webContent.blockedByFilter = .all()
        
        DispatchQueue.main.async {
            self.isRestrictionEnabled = true
            print("アプリ制限を有効化しました")
            self.logDebugInfo()
        }
    }
    
    // 制限を無効化
    private func disableRestriction() {
        // すべての制限を解除
        store.clearAllSettings()
        
        DispatchQueue.main.async {
            self.isRestrictionEnabled = false
            print("アプリ制限を無効化しました")
            self.logDebugInfo()
        }
    }
    
    // Secure Bubble内での自動制限有効化
    func enableRestrictionForSecureBubble() {
        guard isUWBLinked else { return }
        enableRestriction()
    }
    
    // Secure Bubble外での自動制限無効化
    func disableRestrictionForSecureBubble() {
        guard isUWBLinked else { return }
        disableRestriction()
    }
    
    // 選択されたアプリの数を取得
    var selectedAppsCount: Int {
        return activitySelectionStore.selection.applicationTokens.count
    }
    
    // 選択されたアプリを全て削除
    func clearSelectedApps() {
        activitySelectionStore.clearSelection()
        logDebugInfo()
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
            // App Groupsからアクション情報を取得
            let defaults = UserDefaults(suiteName: "group.com.locationreminder.shieldaction")
            guard let action = defaults?.string(forKey: "pendingAction") else { return }
            
            // アクションを実行
            switch action {
            case "openSettings":
                self.openSettings()
            default:
                break
            }
            
            // 処理済みのアクションを削除
            defaults?.removeObject(forKey: "pendingAction")
            defaults?.removeObject(forKey: "actionTimestamp")
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
        // タイマーは自動的に停止される
    }
}

struct ScreenTimeSettingsView: View {
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingAppSelection = false
    @State private var showingPermissionAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
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
                            showingAppSelection = true
                        } else {
                            showingPermissionAlert = true
                        }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .familyActivityPicker(
            isPresented: $showingAppSelection,
            selection: $screenTimeManager.activitySelectionStore.selection
        )
        .onChange(of: screenTimeManager.activitySelectionStore.selection) { newSelection in
            // 選択が変更されたときのログ出力
            print("アプリ選択が変更されました:")
            print("- アプリ数: \(newSelection.applicationTokens.count)")
            print("- カテゴリ数: \(newSelection.categoryTokens.count)")
            print("- Webドメイン数: \(newSelection.webDomainTokens.count)")
            
            // 選択を永続化
            screenTimeManager.activitySelectionStore.saveSelection()
        }
        .alert("認証が必要です", isPresented: $showingPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("アプリ選択機能を使用するには、Family Controlsの認証が必要です。")
        }
        .onReceive(uwbManager.$isInSecureBubble) { isInBubble in
            // UWB状態が変化してから0.5秒待って処理を実行（チャタリング防止）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // 0.5秒後に再度状態を確認し、変わっていなければ実行
                guard uwbManager.isInSecureBubble == isInBubble else {
                    print("UWB状態が再度変更されたため、アクションをキャンセルしました。")
                    return
                }
                
                // UWB状態変化に応じて制限を自動切り替え
                if screenTimeManager.isUWBLinked && screenTimeManager.isAuthorized {
                    if isInBubble {
                        screenTimeManager.enableRestrictionForSecureBubble()
                    } else {
                        screenTimeManager.disableRestrictionForSecureBubble()
                    }
                }
            }
        }
    }
}

#Preview {
    ScreenTimeSettingsView()
} 