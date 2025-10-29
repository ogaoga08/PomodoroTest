import SwiftUI

struct PermissionOnboardingView: View {
    @ObservedObject var permissionManager = PermissionManager.shared
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @State private var currentStep = 0
    @State private var isRequestingPermission = false
    @State private var previousRequestingPermission: PermissionType? = nil
    @State private var showCategorySelection = false
    @Environment(\.dismiss) private var dismiss
    
    private let permissions: [PermissionType] = [
        .reminders,
        .notifications,
        .bluetooth,
        .screenTime
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景グラデーション
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // プログレスバー
                    ProgressView(value: Double(currentStep), total: Double(permissions.count))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .padding()
                    
                    if currentStep < permissions.count {
                        // 現在の許可説明
                        currentPermissionView
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        
                        // UWBセットアップ進捗表示（Bluetooth許可後）
                        if permissionManager.isSettingUpUWB {
                            VStack(spacing: 12) {
                                Divider()
                                    .padding(.vertical, 8)
                                
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("UWBデバイスをセットアップ中")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text(permissionManager.uwbSetupProgress)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        // 完了画面
                        completionView
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // ボタン
                    VStack(spacing: 16) {
                        if currentStep < permissions.count {
                            // 許可ボタン
                            Button(action: requestCurrentPermission) {
                                HStack {
                                    if isRequestingPermission {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                    }
                                    Text("許可する")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isRequestingPermission)
                            
                            // スキップボタン
                            Button("後で設定する") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    nextStep()
                                }
                            }
                            .foregroundColor(.gray)
                            .disabled(isRequestingPermission)
                        } else {
                            // 完了ボタン
                            Button("開始する") {
                                dismiss()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .font(.headline)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("アプリの設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("スキップ") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
            }
        }
        .onChange(of: permissionManager.currentRequestingPermission) { newValue in
            // 許可リクエストが開始された場合
            if newValue != nil && previousRequestingPermission == nil {
                previousRequestingPermission = newValue
                print("🔄 onChange: リクエスト開始検知 - \(newValue?.displayName ?? "不明")")
            }
            // 許可リクエストが完了した場合（nil になった）
            else if newValue == nil && previousRequestingPermission != nil {
                let completedPermission = previousRequestingPermission?.displayName ?? "不明"
                print("✅ onChange: リクエスト完了検知 - \(completedPermission)")
                previousRequestingPermission = nil
                
                // 少し待機してから次のステップへ（UIの更新と状態確認）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("➡️ 次のステップへ移行")
                    isRequestingPermission = false
                    
                    if currentStep < permissions.count {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            nextStep()
                        }
                    }
                }
            }
        }
        .onChange(of: screenTimeManager.isAuthorized) { isAuth in
            // Screen Time認証が完了し、現在のステップがScreen Timeの場合
            if isAuth && currentStep < permissions.count && permissions[currentStep] == .screenTime {
                print("✅ Screen Time認証完了 - カテゴリ選択画面を表示")
                // 0.5秒後にカテゴリ選択画面を自動表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showCategorySelection = true
                }
            }
        }
        .familyActivityPicker(
            isPresented: $showCategorySelection,
            selection: $screenTimeManager.activitySelectionStore.selection
        )
        .onChange(of: screenTimeManager.activitySelectionStore.selection) { newValue in
            // 選択を保存
            print("📝 カテゴリ選択完了 - 保存中")
            screenTimeManager.activitySelectionStore.saveSelection()
        }
    }
    
    @ViewBuilder
    private var currentPermissionView: some View {
        let permission = permissions[currentStep]
        let status = permissionManager.permissionStatuses[permission] ?? .notDetermined
        
        VStack(spacing: 24) {
            // アイコン
            Image(systemName: permission.iconName)
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .scaleEffect(status == .granted ? 1.2 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: status)
            
            // タイトル
            Text(permission.displayName)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // 説明
            Text(permission.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Screen Timeステップの場合のガイダンス
            if permission == .screenTime {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("重要")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    
                    Text("必ず「ソーシャル」「ゲーム」「エンターテイメント」のカテゴリのみ選択してください")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            // 現在の状態
            HStack {
                Image(systemName: statusIcon(for: status))
                    .foregroundColor(status.color)
                Text("状態: \(status.displayText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 追加情報
            if status == .denied {
                VStack(spacing: 8) {
                    Text("設定アプリから許可を有効にできます")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Button("設定を開く") {
                        permissionManager.openSettings()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var completionView: some View {
        VStack(spacing: 24) {
            // 完了アイコン
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .scaleEffect(1.2)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: true)
            
            Text("設定完了")
                .font(.title)
                .fontWeight(.bold)
            
            Text("アプリの準備が整いました！\n必要に応じて、後から設定画面で許可を変更できます。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // 許可状況の概要
            VStack(alignment: .leading, spacing: 8) {
                Text("許可状況")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                ForEach(permissions, id: \.self) { permission in
                    let status = permissionManager.permissionStatuses[permission] ?? .notDetermined
                    
                    HStack {
                        Image(systemName: permission.iconName)
                            .font(.caption)
                            .foregroundColor(status.color)
                            .frame(width: 20)
                        
                        Text(permission.displayName)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(status.displayText)
                            .font(.caption)
                            .foregroundColor(status.color)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
    
    private func requestCurrentPermission() {
        guard !isRequestingPermission else {
            print("⚠️ 既にリクエスト中です")
            return
        }
        
        let permission = permissions[currentStep]
        print("🎯 オンボーディング: \(permission.displayName)の許可をリクエスト開始")
        
        isRequestingPermission = true
        previousRequestingPermission = permission
        
        // 許可リクエストを実行
        permissionManager.requestPermission(permission)
    }
    
    private func nextStep() {
        if currentStep < permissions.count {
            currentStep += 1
        }
    }
    
    private func statusIcon(for status: PermissionStatus) -> String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .unavailable:
            return "minus.circle.fill"
        }
    }
}

struct PermissionOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionOnboardingView()
    }
}
