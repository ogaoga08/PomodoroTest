import SwiftUI
import EventKit

struct ReminderListSelectionView: View {
    @ObservedObject var taskManager: EventKitTaskManager
    @Binding var isPresented: Bool
    
    @State private var availableLists: [EKCalendar] = []
    @State private var selectedList: EKCalendar?
    @State private var isLoading = true
    @State private var showingCreateListAlert = false
    @State private var newListName = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("リマインダーリストを読み込み中...")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableLists.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("リマインダーリストが見つかりません")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("新しいリストを作成するか、リマインダーアプリでリストを作成してから再度お試しください。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Button("新しいリストを作成") {
                                showingCreateListAlert = true
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                            
                            Button("再読み込み") {
                                loadAvailableLists()
                            }
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("リマインダーリストを選択")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("このアプリで使用するリマインダーリストを選択してください。選択したリストでタスクが管理されます。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.red)
                                Text("注意")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            
                            Text("実験用リストを選択してください。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("実験中はリストを変更しないでください！")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        List(availableLists, id: \.calendarIdentifier) { list in
                            ReminderListRowView(
                                list: list,
                                isSelected: selectedList?.calendarIdentifier == list.calendarIdentifier
                            ) {
                                selectedList = list
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                        
                        // 新規リスト作成ボタン
                        Button("新しいリストを作成") {
                            showingCreateListAlert = true
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("リスト選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        if let selected = selectedList {
                            taskManager.setSelectedReminderList(selected)
                            isPresented = false
                        }
                    }
                    .disabled(selectedList == nil)
                    .fontWeight(.semibold)
                }
            }
            .alert("新しいリストを作成", isPresented: $showingCreateListAlert) {
                TextField("リスト名を入力", text: $newListName)
                Button("キャンセル") {
                    newListName = ""
                }
                Button("作成") {
                    createNewList()
                }
                .disabled(newListName.isEmpty)
            } message: {
                Text("新しいリマインダーリストの名前を入力してください。")
            }
            .alert("エラー", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            loadAvailableLists()
        }
    }
    
    private func loadAvailableLists() {
        isLoading = true
        availableLists = taskManager.getAvailableReminderLists()
        
        // 現在選択されているリストがあれば初期選択にする
        if let currentList = taskManager.getCurrentReminderList() {
            selectedList = availableLists.first { $0.calendarIdentifier == currentList.calendarIdentifier }
        }
        
        isLoading = false
    }
    
    private func createNewList() {
        guard !newListName.isEmpty else { return }
        
        do {
            let newCalendar = try taskManager.createNewReminderList(named: newListName)
            
            // リストを再読み込み
            loadAvailableLists()
            
            // 新しく作成されたリストを自動選択
            selectedList = newCalendar
            
            // 入力フィールドをリセット
            newListName = ""
            
        } catch {
            errorMessage = "リストの作成に失敗しました: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct ReminderListRowView: View {
    let list: EKCalendar
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(list.source.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ReminderListSelectionView(
        taskManager: EventKitTaskManager(),
        isPresented: .constant(true)
    )
} 
