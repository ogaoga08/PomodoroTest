import SwiftUI

struct AddTaskView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var memo = ""
    @State private var dueDate = Date()
    @State private var hasTime = false
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationView {
                ScrollView {
                    VStack(spacing: 0) {
                        // ヘッダー
                        HStack {
                            Button("キャンセル") {
                                dismiss()
                            }
                            .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Text("新しいタスク")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button("追加") {
                                let newTask = TaskItem(
                                    title: title,
                                    memo: memo,
                                    dueDate: dueDate,
                                    hasTime: hasTime
                                )
                                taskManager.addTask(newTask)
                                dismiss()
                            }
                            .foregroundColor(title.isEmpty ? .gray : .blue)
                            .disabled(title.isEmpty)
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
                            
                            // 期限設定
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("取り組む日時")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Toggle("時刻を設定", isOn: $hasTime)
                                        .font(.caption)
                                }
                                
                                if hasTime {
                                    DatePicker("期限日時", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                } else {
                                    DatePicker("期限日", selection: $dueDate, displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
