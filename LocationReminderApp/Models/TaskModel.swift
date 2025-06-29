import Foundation
import SwiftUI
import EventKit

struct TaskItem: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var memo: String
    var dueDate: Date
    var hasTime: Bool = false // 時刻が設定されているかどうか
    var isCompleted: Bool = false
    var completedDate: Date?
    var eventKitIdentifier: String? // EventKitのリマインダーIDを保存
    
    // 明示的な初期化子
    init(title: String, memo: String, dueDate: Date, hasTime: Bool = false) {
        self.title = title
        self.memo = memo
        self.dueDate = dueDate
        self.hasTime = hasTime
    }
    
    // EventKitのリマインダーから作成するイニシャライザー
    init(from reminder: EKReminder) {
        self.title = reminder.title ?? ""
        self.memo = reminder.notes ?? ""
        self.hasTime = reminder.dueDateComponents?.hour != nil
        self.isCompleted = reminder.isCompleted
        self.completedDate = reminder.completionDate
        self.eventKitIdentifier = reminder.calendarItemIdentifier
        
        // 期限日の設定
        if let dueDateComponents = reminder.dueDateComponents {
            let calendar = Calendar.current
            self.dueDate = calendar.date(from: dueDateComponents) ?? Date()
        } else {
            self.dueDate = Date()
        }
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

class EventKitTaskManager: ObservableObject {
    // @Published:データの変更を通知 プロパティが変更されたときに自動でUIに通知
    @Published var tasks: [TaskItem] = []
    @Published var completedTasks: [TaskItem] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isRefreshing: Bool = false // 手動更新中の状態
    
    private let eventStore = EKEventStore()
    private var reminderCalendar: EKCalendar?
    
    init() {
        checkAuthorizationStatus()
        setupEventStoreNotifications()
    }
    
    deinit {
        // 通知の監視を停止
        NotificationCenter.default.removeObserver(self)
    }
    
    // EventKitの変更通知を設定
    private func setupEventStoreNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    // EventKitの変更を検知した時の処理
    @objc private func eventStoreChanged() {
        DispatchQueue.main.async {
            print("EventKitの変更を検知しました - リマインダーを再読み込みします")
            self.loadReminders()
        }
    }
    
    // 手動更新メソッド
    func refreshReminders() {
        DispatchQueue.main.async {
            self.isRefreshing = true
        }
        
        // 少し遅延を入れてUI的に更新感を演出
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadReminders()
            self.isRefreshing = false
        }
    }
    
    private func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        
        switch authorizationStatus {
        case .authorized:
            setupCalendar()
            loadReminders()
        case .notDetermined:
            requestAccess()
        case .denied, .restricted:
            print("リマインダーアクセスが拒否されています")
        @unknown default:
            if #available(iOS 17.0, *) {
                switch authorizationStatus {
                case .fullAccess:
                    setupCalendar()
                    loadReminders()
                case .writeOnly:
                    print("書き込み専用アクセス")
                    setupCalendar()
                    loadReminders()
                default:
                    print("不明な認証状態")
                }
            } else {
                print("不明な認証状態")
            }
        }
    }
    
    private func requestAccess() {
        eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
            DispatchQueue.main.async {
                if granted {
                    self?.authorizationStatus = .authorized
                    self?.setupCalendar()
                    self?.loadReminders()
                } else {
                    self?.authorizationStatus = .denied
                    print("リマインダーアクセスが拒否されました: \(error?.localizedDescription ?? "")")
                }
            }
        }
    }
    
    private func setupCalendar() {
        // アプリ専用のリマインダーリストを作成または取得
        let calendars = eventStore.calendars(for: .reminder)
        
        if let existingCalendar = calendars.first(where: { $0.title == "LocationReminder" }) {
            reminderCalendar = existingCalendar
        } else {
            // 新しいリマインダーリストを作成
            let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
            newCalendar.title = "LocationReminder"
            newCalendar.source = eventStore.defaultCalendarForNewReminders()?.source
            
            do {
                try eventStore.saveCalendar(newCalendar, commit: true)
                reminderCalendar = newCalendar
            } catch {
                print("リマインダーリストの作成に失敗しました: \(error)")
                // フォールバックとしてデフォルトのリマインダーリストを使用
                reminderCalendar = eventStore.defaultCalendarForNewReminders()
            }
        }
    }
    
    func loadReminders() {
        guard authorizationStatus == .authorized else { return }
        
        let predicate = eventStore.predicateForReminders(in: [reminderCalendar].compactMap { $0 })
        
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            DispatchQueue.main.async {
                guard let reminders = reminders else { return }
                
                let activeTasks = reminders.filter { !$0.isCompleted }.map { TaskItem(from: $0) }
                let completedTasks = reminders.filter { $0.isCompleted }.map { TaskItem(from: $0) }
                
                self?.tasks = activeTasks
                self?.completedTasks = completedTasks
            }
        }
    }
    
    func addTask(_ task: TaskItem) {
        guard authorizationStatus == .authorized,
              let calendar = reminderCalendar else { return }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = task.title
        reminder.notes = task.memo
        reminder.calendar = calendar
        
        // 期限日の設定
        var components = Calendar.current.dateComponents([.year, .month, .day], from: task.dueDate)
        if task.hasTime {
            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: task.dueDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            // 時刻が設定されている場合、指定時刻にアラームを設定
            let alarm = EKAlarm(absoluteDate: task.dueDate)
            reminder.addAlarm(alarm)
        } else {
            // 時刻が設定されていない場合、その日の9:00にアラームを設定
            var alarmComponents = components
            alarmComponents.hour = 9
            alarmComponents.minute = 0
            if let alarmDate = Calendar.current.date(from: alarmComponents) {
                let alarm = EKAlarm(absoluteDate: alarmDate)
                reminder.addAlarm(alarm)
            }
        }
        reminder.dueDateComponents = components
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders() // リマインダーを再読み込み
        } catch {
            print("リマインダーの保存に失敗しました: \(error)")
        }
    }
    
    func updateTask(_ task: TaskItem) {
        guard authorizationStatus == .authorized,
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        
        reminder.title = task.title
        reminder.notes = task.memo
        
        // 既存のアラームを削除
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        
        // 期限日の更新
        var components = Calendar.current.dateComponents([.year, .month, .day], from: task.dueDate)
        if task.hasTime {
            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: task.dueDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            // 時刻が設定されている場合、指定時刻にアラームを設定
            let alarm = EKAlarm(absoluteDate: task.dueDate)
            reminder.addAlarm(alarm)
        } else {
            // 時刻が設定されていない場合、その日の9:00にアラームを設定
            var alarmComponents = components
            alarmComponents.hour = 9
            alarmComponents.minute = 0
            if let alarmDate = Calendar.current.date(from: alarmComponents) {
                let alarm = EKAlarm(absoluteDate: alarmDate)
                reminder.addAlarm(alarm)
            }
        }
        reminder.dueDateComponents = components
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders()
        } catch {
            print("リマインダーの更新に失敗しました: \(error)")
        }
    }
    
    func deleteTask(_ task: TaskItem) {
        guard authorizationStatus == .authorized,
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        
        do {
            try eventStore.remove(reminder, commit: true)
            loadReminders()
        } catch {
            print("リマインダーの削除に失敗しました: \(error)")
        }
    }
    
    func completeTask(_ task: TaskItem) {
        guard authorizationStatus == .authorized,
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        
        reminder.isCompleted = true
        reminder.completionDate = Date()
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders()
        } catch {
            print("リマインダーの完了処理に失敗しました: \(error)")
        }
    }
    
    func uncompleteTask(_ task: TaskItem) {
        guard authorizationStatus == .authorized,
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        
        reminder.isCompleted = false
        reminder.completionDate = nil
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders()
        } catch {
            print("リマインダーの未完了処理に失敗しました: \(error)")
        }
    }
}

// 後方互換性のために既存のTaskManagerを残す（段階的移行用）
typealias TaskManager = EventKitTaskManager 