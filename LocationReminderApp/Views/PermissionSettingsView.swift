import SwiftUI

struct PermissionSettingsView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var showingPermissionOnboarding = false
    
    var body: some View {
        NavigationView {
            List {
                // 許可状態の概要セクション
                Section("許可状態の概要") {
                    Button(action: { showingPermissionOnboarding = true }) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("すべての許可を再設定")
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
                    
                    // 全体の許可状況
                    HStack {
                        Image(systemName: permissionManager.allRequiredPermissionsGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(permissionManager.allRequiredPermissionsGranted ? .green : .orange)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アプリの動作状況")
                                .foregroundColor(.primary)
                            
                            Text(permissionManager.allRequiredPermissionsGranted ? "正常に動作します" : "一部機能が制限されています")
                                .font(.caption)
                                .foregroundColor(permissionManager.allRequiredPermissionsGranted ? .green : .orange)
                        }
                        
                        Spacer()
                    }
                }
                
                // アプリ許可
                Section("アプリ許可") {
                    PermissionRowView(permission: .reminders, permissionManager: permissionManager)
                    PermissionRowView(permission: .notifications, permissionManager: permissionManager)
                    PermissionRowView(permission: .bluetooth, permissionManager: permissionManager)
                    PermissionRowView(permission: .screenTime, permissionManager: permissionManager)
                }
                
                // 設定アクションセクション
                Section("設定") {
                    Button(action: {
                        permissionManager.openSettings()
                    }) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.gray)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("システム設定を開く")
                                    .foregroundColor(.primary)
                                
                                Text("設定アプリで詳細な許可を管理できます")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    
                    Button(action: {
                        permissionManager.checkAllPermissionStatuses()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("許可状態を更新")
                                    .foregroundColor(.primary)
                                
                                Text("最新の許可状態を取得します")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                // ヘルプセクション
                Section("許可について") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("必要な許可")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("全ての許可はアプリの機能に必要です")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("位置情報について")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("位置ベースのリマインダーを利用するには「常に許可」が推奨されます")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("プライバシー")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("許可された情報はアプリ内でのみ使用され、外部に送信されません")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("アプリ許可設定")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                permissionManager.checkAllPermissionStatuses()
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingPermissionOnboarding) {
            PermissionOnboardingView()
        }
        .onAppear {
            // 許可状態を更新
            permissionManager.checkAllPermissionStatuses()
        }
    }
}

struct PermissionRowView: View {
    let permission: PermissionType
    @ObservedObject var permissionManager: PermissionManager
    
    var status: PermissionStatus {
        permissionManager.permissionStatuses[permission] ?? .notDetermined
    }
    
    var body: some View {
        HStack {
            Image(systemName: permission.iconName)
                .foregroundColor(status.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.displayName)
                    .foregroundColor(.primary)
                    .font(.subheadline)
                
                Text(permission.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("状態: \(status.displayText)")
                        .font(.caption)
                        .foregroundColor(status.color)
                    
                    if permissionManager.currentRequestingPermission == permission {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                if status == .denied || status == .restricted {
                    Button("設定") {
                        permissionManager.openSettings()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if status == .notDetermined {
                    Button("許可") {
                        permissionManager.requestPermission(permission)
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(permissionManager.currentRequestingPermission == permission)
                } else if status == .granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if status == .unavailable {
                    Text("非対応")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PermissionSettingsView()
}
