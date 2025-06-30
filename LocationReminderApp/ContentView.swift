import SwiftUI
import EventKit

struct ContentView: View {
    @StateObject private var taskManager = TaskManager()
    @ObservedObject private var uwbManager = UWBManager.shared

    @State private var showingAddTask = false
    @State private var selectedTask: TaskItem? = nil
    @State private var showingCompletedTasks = false
    @State private var showingUWBSettings = false
    
    // チェックボタンの遅延機能用
    @State private var pendingCompletions: [UUID: Timer] = [:]
    @State private var temporaryCompletedTasks: Set<UUID> = []
    
    var todayTasks: [TaskItem] {
        taskManager.tasks.filter { 
            Calendar.current.isDateInToday($0.dueDate) || $0.dueDate < Calendar.current.startOfDay(for: Date())
        }
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
                if taskManager.authorizationStatus == .denied || taskManager.authorizationStatus == .restricted {
                    // 権限が拒否された場合の表示
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("リマインダーアクセスが必要です")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("このアプリはAppleの標準リマインダーアプリと連携して動作します。設定からリマインダーへのアクセスを許可してください。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button("設定を開く") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding()
                } else if taskManager.authorizationStatus == .notDetermined {
                    // 権限確認中の表示
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("リマインダーアクセスを確認中...")
                            .font(.headline)
                    }
                } else if isAuthorizedForReminders(taskManager.authorizationStatus) {
                    // 通常のタスク表示
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
                                        TaskRowView(
                                            task: task,
                                            isTemporarilyCompleted: temporaryCompletedTasks.contains(task.id),
                                            onTap: { selectedTask = task },
                                            onComplete: { handleTaskCompletion(task) }
                                        )
                                        .swipeActions(edge: .trailing) {
                                            Button("削除", role: .destructive) {
                                                taskManager.deleteTask(task)
                                            }
                                        }
                                         .swipeActions(edge: .leading) {
                                             Button("完了") {
                                                 taskManager.completeTask(task)
                                             }
                                             .tint(.green)
                                         }
                                    }
                                } header: {
                                    Text("今日のタスク")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .textCase(nil)
                                }
                            }
                            
                            if !futureTasks.isEmpty {
                                Section {
                                    ForEach(futureTasks) { task in
                                        TaskRowView(
                                            task: task,
                                            isTemporarilyCompleted: temporaryCompletedTasks.contains(task.id),
                                            onTap: { selectedTask = task },
                                            onComplete: { handleTaskCompletion(task) }
                                        )
                                        .swipeActions(edge: .trailing) {
                                            Button("削除", role: .destructive) {
                                                taskManager.deleteTask(task)
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button("完了") {
                                                taskManager.completeTask(task)
                                            }
                                            .tint(.green)
                                        }
                                    }
                                } header: {
                                    Text("明日以降のタスク")
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
                                                CompletedTaskRowView(task: task) {
                                                    selectedTask = task
                                                }
                                                .swipeActions(edge: .trailing) {
                                                    Button("戻す") {
                                                        taskManager.uncompleteTask(task)
                                                    }
                                                    .tint(.orange)
                                                }
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
                            
                            if taskManager.tasks.isEmpty && isAuthorizedForReminders(taskManager.authorizationStatus) {
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
                        .refreshable {
                            // プルツーリフレッシュによる手動更新
                            await withCheckedContinuation { continuation in
                                taskManager.refreshReminders()
                                
                                // isRefreshingの変化を監視して完了を通知
                                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                                    if !taskManager.isRefreshing {
                                        timer.invalidate()
                                        continuation.resume()
                                    }
                                }
                            }
                        }
                    }
                    
                    // 追加ボタン（権限がある場合のみ表示）
                    if isAuthorizedForReminders(taskManager.authorizationStatus) {
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
                } else {
                    // 未知の認証状態
                    VStack(spacing: 20) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("認証状態を確認できません")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("しばらく待ってから再度お試しください。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
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
                                        
                                        Text("通信中")
                                                                            .foregroundColor(.orange.opacity(0.8))
                                                                                        .font(.caption2)
//                                        if let distance = uwbManager.currentDistance {
//                                            Text(String(format: "%.2fm", distance))
//                                                .foregroundColor(.orange.opacity(0.8))
//                                                .font(.caption2)
//                                        } else {
//                                            Text("-.--m")
//                                                .foregroundColor(.orange.opacity(0.8))
//                                                .font(.caption2)
//                                        }
                                    }
                                    
//                                    // Secure Bubble状態表示
//                                    VStack(alignment: .leading, spacing: 1) {
//                                        Text("部屋")
//                                            .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
//                                            .fontWeight(.medium)
//                                            .font(.caption)
//                                        Text(uwbManager.isInSecureBubble ? "入室中" : "退室中")
//                                            .foregroundColor(uwbManager.isInSecureBubble ? .green.opacity(0.8) : .red.opacity(0.8))
//                                            .font(.caption2)
//                                    }
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
                    NavigationLink(destination: MenuView()) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                    }
                }
            })
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
            } else if let completedTaskIndex = taskManager.completedTasks.firstIndex(where: { $0.id == task.id }) {
                TaskDetailView(task: $taskManager.completedTasks[completedTaskIndex], taskManager: taskManager)
            }
        }
        .sheet(isPresented: $showingUWBSettings) {
            UWBSettingsView()
        }
        .onAppear {
            // UWBManagerにTaskManagerの参照を設定
            uwbManager.taskManager = taskManager
        }
        .environmentObject(taskManager)
    }
    
    // タスク完了の遅延処理
    private func handleTaskCompletion(_ task: TaskItem) {
        // 既にタイマーが設定されている場合はキャンセル
        if let existingTimer = pendingCompletions[task.id] {
            existingTimer.invalidate()
            pendingCompletions.removeValue(forKey: task.id)
            temporaryCompletedTasks.remove(task.id)
            return
        }
        
        // 一時的に完了状態にする
        temporaryCompletedTasks.insert(task.id)
        
        // 2秒後に実際の完了処理を実行
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            taskManager.completeTask(task)
            pendingCompletions.removeValue(forKey: task.id)
            temporaryCompletedTasks.remove(task.id)
        }
        
        pendingCompletions[task.id] = timer
    }
}

// ヘルパー関数：認証状態が有効かどうかを判定
private func isAuthorizedForReminders(_ status: EKAuthorizationStatus) -> Bool {
    if #available(iOS 17.0, *) {
        return status == .authorized || status == .fullAccess || status == .writeOnly
    } else {
        return status == .authorized
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let isTemporarilyCompleted: Bool
    let onTap: () -> Void
    let onComplete: () -> Void
    
    private var isShowingAsCompleted: Bool {
        task.isCompleted || isTemporarilyCompleted
    }
    
    private var isOverdue: Bool {
        task.dueDate < Calendar.current.startOfDay(for: Date())
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左側：チェックボタン
            Button(action: onComplete) {
                Image(systemName: isShowingAsCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isShowingAsCompleted ? .green : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(PlainButtonStyle())
            
            // 中央：タスク情報
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .strikethrough(isShowingAsCompleted)
                
                if !task.memo.isEmpty {
                    Text(task.memo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text(task.formattedDueDate)
                    .font(.caption)
                    .foregroundColor(isOverdue ? .red : .secondary)
            }
            
            Spacer()
            
            // 右側：詳細ボタン
            Button(action: onTap) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .opacity(isShowingAsCompleted ? 0.6 : 1.0)
    }
}

struct CompletedTaskRowView: View {
    let task: TaskItem
    let onTap: () -> Void
    
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
            
            // 詳細ボタン
            Button(action: onTap) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
} 
