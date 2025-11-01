import SwiftUI

struct InitialTaskSetupView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedStartDate = Date()
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
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
                    // スクロール可能なコンテンツ
                    ScrollView {
                        VStack(spacing: 24) {
                            // アイコン
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                                .padding(.top, 20)
                            
                            // タイトル
                            VStack(spacing: 8) {
                                Text("実験開始日の設定")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text("1日目をいつにするか選択してください")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            // 説明
                            VStack(alignment: .leading, spacing: 12) {
                                Text("初期タスクについて")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("英単語課題：14日間（毎日17:00）")
                                            .font(.caption)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("一般教養課題：14日間（毎日17:00）")
                                            .font(.caption)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("動画視聴課題：4日目・11日目（17:00）")
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
//                            .background(Color.gray.opacity(0.98))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            
                            // 日付選択
                            VStack(spacing: 8) {
                                Text("1日目の日付")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                DatePicker(
                                    "",
                                    selection: $selectedStartDate,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .padding(8)
//                                .background(Color.secondary.opacity(0.98))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                            
                            // 余白（ボタンとの間）
                            Color.clear.frame(height: 80)
                        }
                    }
                    
                    // 固定ボタン（画面下部）
                    VStack(spacing: 0) {
                        Divider()
                        
                        Button(action: createInitialTasks) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                Text(isCreating ? "作成中..." : "タスクを作成")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCreating ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isCreating)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground).opacity(0.95))
                    }
                }
            }
            .navigationTitle("初期設定")
            .navigationBarTitleDisplayMode(.inline)
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createInitialTasks() {
        isCreating = true
        
        // 少し遅延を入れてUIの更新を確実にする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            do {
                // 「実験用リスト」を作成
                _ = try taskManager.createExperimentalReminderList()
                
                // 選択された開始日から初期タスクを作成
                taskManager.createInitialTasks(from: selectedStartDate)
                
                // 少し待ってからタスクを再読み込み
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    taskManager.loadReminders()
                    
                    // さらに少し待ってから画面を閉じる
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isCreating = false
                        dismiss()
                    }
                }
            } catch {
                isCreating = false
                errorMessage = "初期タスクの作成に失敗しました: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

#Preview {
    InitialTaskSetupView(taskManager: TaskManager())
}

