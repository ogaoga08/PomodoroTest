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
    @State private var editedPriority: TaskPriority = .none
    @State private var editedRecurrenceType: RecurrenceType = .none
    
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
                                .background(Color(.systemGray5))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("優先度")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(TaskPriority.allCases) { priorityOption in
                                        Button(action: {
                                            editedPriority = priorityOption
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: priorityOption.symbolName)
                                                    .foregroundColor(editedPriority == priorityOption ? .white : priorityOption.color)
                                                    .font(.caption)
                                                
                                                Text(priorityOption.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(editedPriority == priorityOption ? .white : .primary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                editedPriority == priorityOption
                                                    ? priorityOption.color
                                                    : Color(.systemGray5)
                                            )
                                            .cornerRadius(16)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.horizontal, -16)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("メモ")
                                .font(.headline)
                            if #available(iOS 16.0, *) {
                                TextField("メモ", text: $editedMemo, axis: .vertical)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(12)
                                    .lineLimit(3...6)
                            } else {
                                TextField("メモ", text: $editedMemo)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
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
                                    .environment(\.locale, Locale(identifier: "ja_JP"))
                                    .onAppear {
                                        // 5分刻みに設定
                                        UIDatePicker.appearance().minuteInterval = 5
                                    }
                            } else {
                                DatePicker("期限日", selection: $editedDueDate, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "ja_JP"))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("繰り返し")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(RecurrenceType.allCases) { recurrenceOption in
                                        Button(action: {
                                            editedRecurrenceType = recurrenceOption
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: recurrenceOption.symbolName)
                                                    .foregroundColor(editedRecurrenceType == recurrenceOption ? .white : .blue)
                                                    .font(.caption)
                                                
                                                Text(recurrenceOption.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(editedRecurrenceType == recurrenceOption ? .white : .primary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                editedRecurrenceType == recurrenceOption
                                                    ? Color.blue
                                                    : Color(.systemGray5)
                                            )
                                            .cornerRadius(16)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.horizontal, -16)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
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
            .onTapGesture {
                // キーボードを閉じる
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onAppear {
            editedTitle = task.title
            editedMemo = task.memo
            editedDueDate = task.dueDate
            editedHasTime = task.hasTime
            editedPriority = task.priority
            editedRecurrenceType = task.recurrenceType
        }
    }
    
    private func saveChanges() {
        var updatedTask = task
        updatedTask.title = editedTitle
        updatedTask.memo = editedMemo
        updatedTask.dueDate = editedDueDate
        updatedTask.hasTime = editedHasTime
        updatedTask.priority = editedPriority
        updatedTask.recurrenceType = editedRecurrenceType
        
        taskManager.updateTask(updatedTask)
    }
}

#Preview {
    TaskDetailView(
        task: .constant(TaskItem(title: "サンプルタスク", memo: "これはサンプルのメモです", dueDate: Date(), hasTime: false)),
        taskManager: TaskManager()
    )
} 
