import SwiftUI

struct AddTaskView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var memo = ""
    @State private var dueDate = Date()
    @State private var hasTime = false
    @State private var priority: TaskPriority = .none
    @State private var recurrenceType: RecurrenceType = .none
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationView {
                ScrollView {
                    VStack(spacing: 0) {
                        // ヘッダー
                        ZStack {
                            HStack {
                                Button("キャンセル") {
                                    dismiss()
                                }
                                .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Button("追加") {
                                    let newTask = TaskItem(
                                        title: title,
                                        memo: memo,
                                        dueDate: dueDate,
                                        hasTime: hasTime,
                                        priority: priority,
                                        recurrenceType: recurrenceType
                                    )
                                    taskManager.addTask(newTask)
                                    dismiss()
                                }
                                .foregroundColor(title.isEmpty ? .gray : .blue)
                                .disabled(title.isEmpty)
                            }
                            
                            Text("新しいタスク")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(.systemBackground))
                        
                        // コンテンツ
                        VStack(spacing: 24) {
                            // タスク名
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("タスク名を入力", text: $title)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(12)
                                    .font(.body)
                            }
                            
                            // メモ
                            VStack(alignment: .leading, spacing: 12) {
                                if #available(iOS 16.0, *) {
                                    TextField("メモを入力（オプション）", text: $memo, axis: .vertical)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(12)
                                        .font(.body)
                                        .lineLimit(3...6)
                                } else {
                                    TextField("メモを入力（オプション）", text: $memo)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(12)
                                        .font(.body)
                                }
                            }
                            
                            // 優先度設定
                            VStack(alignment: .leading, spacing: 12) {
                                Text("優先度")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(TaskPriority.allCases) { priorityOption in
                                            Button(action: {
                                                priority = priorityOption
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: priorityOption.symbolName)
                                                        .foregroundColor(priority == priorityOption ? .white : priorityOption.color)
                                                        .font(.caption)
                                                    
                                                    Text(priorityOption.displayName)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(priority == priorityOption ? .white : .primary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    priority == priorityOption
                                                        ? priorityOption.color
                                                        : Color(.systemGray5)
                                                )
                                                .cornerRadius(16)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .padding(.horizontal, -20)
                            }
                            
                            // 期限設定
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("取り組む日時")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        Text("時刻を設定")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Toggle("", isOn: $hasTime)
                                            .labelsHidden()
                                    }
                                }
                                
                                if hasTime {
                                    DatePicker("期限日時", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .environment(\.locale, Locale(identifier: "ja_JP"))
                                        .onAppear {
                                            // 5分刻みに設定
                                            UIDatePicker.appearance().minuteInterval = 5
                                        }
                                } else {
                                    DatePicker("期限日", selection: $dueDate, displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .environment(\.locale, Locale(identifier: "ja_JP"))
                                }
                            }
                            
                            // 繰り返し設定
                            VStack(alignment: .leading, spacing: 12) {
                                Text("繰り返し")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(RecurrenceType.allCases) { recurrenceOption in
                                            Button(action: {
                                                recurrenceType = recurrenceOption
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: recurrenceOption.symbolName)
                                                        .foregroundColor(recurrenceType == recurrenceOption ? .white : .blue)
                                                        .font(.caption)
                                                    
                                                    Text(recurrenceOption.displayName)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(recurrenceType == recurrenceOption ? .white : .primary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    recurrenceType == recurrenceOption
                                                        ? Color.blue
                                                        : Color(.systemGray5)
                                                )
                                                .cornerRadius(16)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .padding(.horizontal, -20)
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onTapGesture {
                    // キーボードを閉じる
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        } else {
            // Fallback on earlier versions
        }
    }
}

#Preview {
    AddTaskView(taskManager: TaskManager())
} 
