import SwiftUI

// Screen Time管理クラス（仮実装）
class ScreenTimeManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var isRestrictionEnabled = false
    @Published var selectedApps: [MockAppInfo] = []
    @Published var isUWBLinked = true
    @Published var authorizationStatus = "未認証"
    
    func requestAuthorization() {
        // 実際の実装では FamilyControls.AuthorizationCenter.shared.requestAuthorization() を使用
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 仮の認証成功
            self.isAuthorized = true
            self.authorizationStatus = "認証済み"
        }
    }
    
    func toggleRestriction() {
        isRestrictionEnabled.toggle()
        // 実際の実装では ManagedSettings を使用してアプリ制限を設定
    }
    
    func enableRestrictionForSecureBubble() {
        guard isAuthorized && isUWBLinked else { return }
        isRestrictionEnabled = true
        // 実際の実装:
        // let store = ManagedSettingsStore()
        // store.application.blockedApplications = selectedApps
        // store.shield.applications = selectedApps
    }
    
    func disableRestrictionForSecureBubble() {
        guard isAuthorized && isUWBLinked else { return }
        isRestrictionEnabled = false
        // 実際の実装:
        // let store = ManagedSettingsStore()
        // store.clearAllSettings()
    }
}

// モックアプリ情報
struct MockAppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let iconName: String
}

struct ScreenTimeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingAppSelection = false
    
    // モックアプリデータ
    private let mockApps = [
        MockAppInfo(name: "Instagram", bundleIdentifier: "com.instagram.app", iconName: "camera.circle.fill"),
        MockAppInfo(name: "TikTok", bundleIdentifier: "com.tiktok.app", iconName: "video.circle.fill"),
        MockAppInfo(name: "Twitter", bundleIdentifier: "com.twitter.app", iconName: "message.circle.fill"),
        MockAppInfo(name: "YouTube", bundleIdentifier: "com.youtube.app", iconName: "play.circle.fill"),
        MockAppInfo(name: "Safari", bundleIdentifier: "com.apple.safari", iconName: "safari.fill"),
        MockAppInfo(name: "Chrome", bundleIdentifier: "com.google.chrome", iconName: "globe.circle.fill")
    ]
    
    var body: some View {
        NavigationView {
            List {
                // 認証セクション
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: screenTimeManager.isAuthorized ? "checkmark.shield.fill" : "shield.slash.fill")
                                .foregroundColor(screenTimeManager.isAuthorized ? .green : .red)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Family Controls認証")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(screenTimeManager.authorizationStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !screenTimeManager.isAuthorized {
                                Button("認証") {
                                    screenTimeManager.requestAuthorization()
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                        }
                        
                        if !screenTimeManager.isAuthorized {
                            Text("⚠️ Family Controls APIの使用には、Appleからの特別な許可が必要です。通常、保護者制御アプリや組織管理アプリでのみ承認されます。")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("認証状態")
                }
                
                // UWB連動設定
                Section {
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
                    .padding(.vertical, 4)
                    
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
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("UWB連動設定")
                } footer: {
                    Text("有効にすると、Secure Bubble内にいる時に自動的にアプリ制限が適用されます。")
                }
                
                // アプリ選択
                Section {
                    Button(action: {
                        showingAppSelection = true
                    }) {
                        HStack {
                            Image(systemName: "apps.iphone")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("制限するアプリを選択")
                                    .foregroundColor(.primary)
                                    .font(.headline)
                                
                                if screenTimeManager.selectedApps.isEmpty {
                                    Text("未選択")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(screenTimeManager.selectedApps.count)個のアプリを選択済み")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!screenTimeManager.isAuthorized)
                    
                    // 選択されたアプリ一覧
                    if !screenTimeManager.selectedApps.isEmpty {
                        ForEach(screenTimeManager.selectedApps, id: \.id) { app in
                            HStack {
                                Image(systemName: app.iconName)
                                    .foregroundColor(.blue)
                                Text(app.name)
                                    .font(.subheadline)
                                Spacer()
                                Button("削除") {
                                    screenTimeManager.selectedApps.removeAll { $0.id == app.id }
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("制限対象アプリ")
                } footer: {
                    Text("実際の実装では、FamilyControls.FamilyActivityPickerを使用してユーザーがアプリを選択します。")
                }
                
                // 制御状態
                Section {
                    HStack {
                        Image(systemName: screenTimeManager.isRestrictionEnabled ? "lock.fill" : "lock.open.fill")
                            .foregroundColor(screenTimeManager.isRestrictionEnabled ? .red : .green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("制限状態")
                                .font(.headline)
                            Text(screenTimeManager.isRestrictionEnabled ? "制限中" : "制限なし")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(screenTimeManager.isRestrictionEnabled ? "制限解除" : "制限適用") {
                            screenTimeManager.toggleRestriction()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(screenTimeManager.isRestrictionEnabled ? Color.green : Color.red)
                        .cornerRadius(6)
                        .disabled(!screenTimeManager.isAuthorized)
                    }
                } header: {
                    Text("現在の制限状態")
                } footer: {
                    Text("実際の実装では、ManagedSettingsを使用してShieldConfigurationでアプリをブロックします。")
                }
            }
            .navigationTitle("Screen Time設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAppSelection) {
            AppSelectionView(
                selectedApps: $screenTimeManager.selectedApps,
                availableApps: mockApps
            )
        }
        .onReceive(uwbManager.$isInSecureBubble) { isInBubble in
            // UWB状態変化に応じて制限を切り替え
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

// アプリ選択画面
struct AppSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedApps: [MockAppInfo]
    let availableApps: [MockAppInfo]
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("⚠️ これはプレビュー画面です。実際の実装では、FamilyControls.FamilyActivityPickerを使用してシステムのアプリ選択画面を表示します。")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                } header: {
                    Text("注意事項")
                }
                
                Section {
                    ForEach(availableApps, id: \.id) { app in
                        HStack {
                            Image(systemName: app.iconName)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.headline)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedApps.contains(where: { $0.id == app.id }) {
                                Button("削除") {
                                    selectedApps.removeAll { $0.id == app.id }
                                }
                                .foregroundColor(.red)
                            } else {
                                Button("追加") {
                                    selectedApps.append(app)
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("利用可能なアプリ")
                }
            }
            .navigationTitle("アプリ選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ScreenTimeSettingsView()
} 