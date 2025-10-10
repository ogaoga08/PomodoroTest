import SwiftUI

struct MenuView: View {
    @ObservedObject var taskManager: TaskManager
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var showingPermissionOnboarding = false
    @State private var showingReminderListSelection = false
    
    var body: some View {
        NavigationView {
            List {

                
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
                    
                    NavigationLink(destination: GeofencingSettingsView()) {
                        HStack {
                            Image(systemName: "location.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("ジオフェンシング設定")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    NavigationLink(destination: PermissionSettingsView()) {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("アプリ許可設定")
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
