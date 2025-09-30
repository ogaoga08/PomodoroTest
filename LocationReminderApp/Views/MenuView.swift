import SwiftUI

struct MenuView: View {
    @ObservedObject var taskManager: TaskManager
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var showingPermissionOnboarding = false
    @State private var showingReminderListSelection = false
    
    var body: some View {
        NavigationView {
            List {
                // 許可状態セクション
                Section("アプリ許可状態") {
                    // 許可状態の概要表示
                    Button(action: { showingPermissionOnboarding = true }) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("許可設定")
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    let grantedCount = permissionManager.permissionStatuses.values.filter { $0 == .granted }.count
                                    let totalCount = PermissionType.allCases.count
                                    
                                    Text("\(grantedCount)/\(totalCount) 許可済み")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !permissionManager.allRequiredPermissionsGranted {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    
                    // 個別許可状態の表示
                    ForEach(PermissionType.allCases, id: \.self) { permission in
                        let status = permissionManager.permissionStatuses[permission] ?? .notDetermined
                        
                        HStack {
                            Image(systemName: permission.iconName)
                                .foregroundColor(status.color)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.displayName)
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                
                                Text(status.displayText)
                                    .font(.caption)
                                    .foregroundColor(status.color)
                            }
                            
                            Spacer()
                            
                            if status == .denied {
                                Button("設定") {
                                    permissionManager.openSettings()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            } else if status == .notDetermined {
                                Button("許可") {
                                    permissionManager.requestPermission(permission)
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                // 機能設定セクション
                Section("機能設定") {
                    // リマインダーリスト変更ボタン（リストが選択済みの場合のみ表示）
                    if !taskManager.needsListSelection {
                        Button(action: { 
                            showingReminderListSelection = true
                        }) {
                            HStack {
                                Image(systemName: "list.bullet.rectangle")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                Text("リマインダーリスト変更")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    NavigationLink(destination: StatisticsView(taskManager: taskManager)) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("統計・分析")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    NavigationLink(destination: UWBSettingsView()) {
                        HStack {
                            Image(systemName: "wave.3.right")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("UWBモジュール設定")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    NavigationLink(destination: ScreenTimeSettingsView()) {
                        HStack {
                            Image(systemName: "hourglass")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text("Screen Time設定")
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                // その他セクション
                Section("その他") {
                    NavigationLink(destination: OnboardingView()) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("本アプリとは")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingPermissionOnboarding) {
            PermissionOnboardingView()
        }
        .sheet(isPresented: $showingReminderListSelection) {
            ReminderListSelectionView(
                taskManager: taskManager,
                isPresented: $showingReminderListSelection
            )
        }
        .onAppear {
            // 許可状態を更新
            permissionManager.checkAllPermissionStatuses()
        }
    }
}

#Preview {
    MenuView(taskManager: TaskManager())
} 
