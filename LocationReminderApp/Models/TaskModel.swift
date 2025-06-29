import Foundation
import SwiftUI

struct TaskItem: Identifiable, Codable, Equatable {
    let id = UUID()
    var title: String
    var memo: String
    var dueDate: Date
    var hasTime: Bool = false // 時刻が設定されているかどうか
    var isCompleted: Bool = false
    var completedDate: Date?
    
    // 明示的な初期化子
    init(title: String, memo: String, dueDate: Date, hasTime: Bool = false) {
        self.title = title
        self.memo = memo
        self.dueDate = dueDate
        self.hasTime = hasTime
    }
    
    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // 時刻表示用のフォーマット済み文字列
    var formattedDueDate: String {
        let formatter = DateFormatter()
        if hasTime {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }
        return formatter.string(from: dueDate)
    }
}

class TaskManager: ObservableObject {
    // @Published:データの変更を通知 プロパティが変更されたときに自動でUIに通知
    @Published var tasks: [TaskItem] = []
    @Published var completedTasks: [TaskItem] = []
    
    private let tasksKey = "saved_tasks"
    private let completedTasksKey = "completed_tasks"
    
    init() {
        loadTasks()
    }
    
    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }
    
    func updateTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveTasks()
        }
    }
    
    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }
    
    func completeTask(_ task: TaskItem) {
        var completedTask = task
        completedTask.isCompleted = true
        completedTask.completedDate = Date()
        
        // タスクリストから削除し、完了リストに追加
        tasks.removeAll { $0.id == task.id }
        completedTasks.append(completedTask)
        
        saveTasks()
        saveCompletedTasks()
    }
    
    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksKey)
        }
    }
    
    private func saveCompletedTasks() {
        if let encoded = try? JSONEncoder().encode(completedTasks) {
            UserDefaults.standard.set(encoded, forKey: completedTasksKey)
        }
    }
    
    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let decodedTasks = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decodedTasks
        }
        
        if let data = UserDefaults.standard.data(forKey: completedTasksKey),
           let decodedTasks = try? JSONDecoder().decode([TaskItem].self, from: data) {
            completedTasks = decodedTasks
        }
    }
} 