import SwiftUI
import EventKit

struct ReminderListSelectionView: View {
    @ObservedObject var taskManager: EventKitTaskManager
    @Binding var isPresented: Bool
    
    @State private var availableLists: [EKCalendar] = []
    @State private var selectedList: EKCalendar?
    @State private var isLoading = true
    
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
                        
                        Text("リマインダーアプリでリストを作成してから再度お試しください。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button("再読み込み") {
                            loadAvailableLists()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
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
                        
                        List(availableLists, id: \.calendarIdentifier) { list in
                            ReminderListRowView(
                                list: list,
                                isSelected: selectedList?.calendarIdentifier == list.calendarIdentifier
                            ) {
                                selectedList = list
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
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