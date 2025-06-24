import SwiftUI

struct ContentView: View {
    @StateObject private var taskManager = TaskManager()
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingMenu = false
    @State private var showingAddTask = false
    @State private var selectedTask: TaskItem? = nil
    @State private var showingCompletedTasks = false
    @State private var showingUWBSettings = false
    
    private var roomStatus: String {
        guard let savedDistance = UserDefaults.standard.object(forKey: "door_distance") as? Float,
              let currentDistance = uwbManager.currentDistance else {
            return "未設定"
        }
        
        return currentDistance <= savedDistance ? "入室中" : "外出中"
    }
    
    private var roomStatusColor: Color {
        switch roomStatus {
        case "入室中":
            return .green
        case "外出中":
            return .orange
        default:
            return .gray
        }
    }
    
    var todayTasks: [TaskItem] {
        taskManager.tasks.filter { Calendar.current.isDateInToday($0.dueDate) }
    }
    
    var futureTasks: [TaskItem] {
        taskManager.tasks.filter { !Calendar.current.isDateInToday($0.dueDate) && $0.dueDate > Date() }
    }
    
    var completionRate: Double {
        let completedTasks = taskManager.completedTasks.count
        let totalTasks = completedTasks + taskManager.tasks.count
        return totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0.0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // ヘッダー統計（改善版）
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            // 残りのタスク（赤ベース）
                            VStack(spacing: 8) {
                                Text("残りのタスク")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                Text("\(todayTasks.count)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            
                            // 期限遂行率（青ベース）
                            VStack(spacing: 8) {
                                Text("期限遂行率")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                Text("\(Int(completionRate * 100))%")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                    .background(Color(.systemGroupedBackground))
                    
                    // タスクリスト
                    List {
                        if !todayTasks.isEmpty {
                            Section {
                                ForEach(todayTasks) { task in
                                    TaskRowView(task: task) {
                                        selectedTask = task
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button("削除", role: .destructive) {
                                            taskManager.deleteTask(task)
                                        }
                                    }
                                }
                            } header: {
                                Text("今日の課題")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                        
                        if !futureTasks.isEmpty {
                            Section {
                                ForEach(futureTasks) { task in
                                    TaskRowView(task: task) {
                                        selectedTask = task
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button("削除", role: .destructive) {
                                            taskManager.deleteTask(task)
                                        }
                                    }
                                }
                            } header: {
                                Text("明日以降の課題")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                        
                        // 完了タスクアコーディオン
                        if !taskManager.completedTasks.isEmpty {
                            Section {
                                DisclosureGroup(
                                    isExpanded: $showingCompletedTasks,
                                    content: {
                                        ForEach(taskManager.completedTasks.reversed()) { task in
                                            CompletedTaskRowView(task: task)
                                        }
                                    },
                                    label: {
                                        HStack {
                                            Text("完了済みタスク")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text("\(taskManager.completedTasks.count)件")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                )
                            }
                        }
                        
                        if taskManager.tasks.isEmpty {
                            Section {
                                VStack {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 50))
                                        .foregroundColor(.secondary)
                                    Text("タスクがありません")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("下のプラスボタンから新しいタスクを追加しましょう")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
                
                // 追加ボタン
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { showingAddTask = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("リマインダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        if uwbManager.isUWBActive {
                            Button(action: { showingUWBSettings = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "wave.3.right.circle.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("UWB")
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                            .font(.caption)
                                        if let distance = uwbManager.currentDistance {
                                            Text(String(format: "%.2fm", distance))
                                                .foregroundColor(.orange.opacity(0.8))
                                                .font(.caption2)
                                        } else {
                                            Text("-.--m")
                                                .foregroundColor(.orange.opacity(0.8))
                                                .font(.caption2)
                                        }
                                    }
                                    
                                    // 部屋の状態表示
                                    if roomStatus != "未設定" {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("部屋")
                                                .foregroundColor(roomStatusColor)
                                                .fontWeight(.medium)
                                                .font(.caption)
                                            Text(roomStatus)
                                                .foregroundColor(roomStatusColor.opacity(0.8))
                                                .font(.caption2)
                                        }
                                    }
                                    
                                    // Secure Bubble状態表示
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Bubble")
                                            .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
                                            .fontWeight(.medium)
                                            .font(.caption)
                                        Text(uwbManager.isInSecureBubble ? "内部" : "外部")
                                            .foregroundColor(uwbManager.isInSecureBubble ? .green.opacity(0.8) : .red.opacity(0.8))
                                            .font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingMenu = true }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                    }
                }
            })
        }
        .sheet(isPresented: $showingMenu) {
            MenuView()
        }
        .sheet(isPresented: $showingAddTask) {
            if #available(iOS 16.0, *) {
                AddTaskView(taskManager: taskManager)
            } else {
                // Fallback on earlier versions
            }
        }
        .sheet(item: $selectedTask) { task in
            if let taskIndex = taskManager.tasks.firstIndex(where: { $0.id == task.id }) {
                TaskDetailView(task: $taskManager.tasks[taskIndex], taskManager: taskManager)
            }
        }
        .sheet(isPresented: $showingUWBSettings) {
            UWBSettingsView()
        }
        .environmentObject(taskManager)
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !task.memo.isEmpty {
                        Text(task.memo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(task.formattedDueDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CompletedTaskRowView: View {
    let task: TaskItem
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .strikethrough()
                
                if let completedDate = task.completedDate {
                    Text("完了: \(completedDate, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
} 
