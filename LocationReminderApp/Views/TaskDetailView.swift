import SwiftUI

struct TaskDetailView: View {
    @Binding var task: TaskItem
    // オブジェクトの変更を監視: @Publishedプロパティの変更を検知
    @ObservedObject var taskManager: TaskManager
    // taskManager.tasksが変更されると、この画面が自動更新される
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedTitle: String = ""
    @State private var editedMemo: String = ""
    @State private var editedDueDate: Date = Date()
    @State private var editedHasTime: Bool = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // タスク編集セクション
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("タスク")
                                .font(.headline)
                            TextField("タスク名", text: $editedTitle)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("メモ")
                                .font(.headline)
                            if #available(iOS 16.0, *) {
                                TextField("メモ", text: $editedMemo, axis: .vertical)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .lineLimit(3...6)
                            } else {
                                TextField("メモ", text: $editedMemo)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("期限")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Toggle("時刻を設定", isOn: $editedHasTime)
                                    .font(.caption)
                            }
                            
                            if editedHasTime {
                                DatePicker("期限日時", selection: $editedDueDate, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            } else {
                                DatePicker("期限日", selection: $editedDueDate, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 80)
                }
            }
            .navigationTitle("タスク編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveChanges()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            })
            .overlay(alignment: .bottom) {
                // 下部ボタン
                HStack(spacing: 20) {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Text("削除")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button(action: {
                        taskManager.completeTask(task)
                        dismiss()
                    }) {
                        Text("完了")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
                .background(Color(.systemBackground))
            }
        }
        .onAppear {
            editedTitle = task.title
            editedMemo = task.memo
            editedDueDate = task.dueDate
            editedHasTime = task.hasTime
        }
        .alert("タスクを削除", isPresented: $showingDeleteAlert) {
            Button("削除", role: .destructive) {
                taskManager.deleteTask(task)
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("このタスクを削除しますか？この操作は取り消せません。")
        }
    }
    
    private func saveChanges() {
        var updatedTask = task
        updatedTask.title = editedTitle
        updatedTask.memo = editedMemo
        updatedTask.dueDate = editedDueDate
        updatedTask.hasTime = editedHasTime
        
        taskManager.updateTask(updatedTask)
    }
}

#Preview {
    TaskDetailView(
        task: .constant(TaskItem(title: "サンプルタスク", memo: "これはサンプルのメモです", dueDate: Date(), hasTime: false)),
        taskManager: TaskManager()
    )
} 