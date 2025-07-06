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
    @Published var needsListSelection: Bool = false // リスト選択が必要かどうか
    
    private let eventStore = EKEventStore()
    private var reminderCalendar: EKCalendar?
    
    // UserDefaultsのキー
    private let selectedListIdentifierKey = "SelectedReminderListIdentifier"
    private let hasSelectedListKey = "HasSelectedReminderList"
    
    init() {
        checkAuthorizationStatus()
        setupEventStoreNotifications()
    }
    
    deinit {
        // 通知の監視を停止
        NotificationCenter.default.removeObserver(self)
    }
    
    // 認証状態をチェックするヘルパー関数
    private func isAuthorized() -> Bool {
        switch authorizationStatus {
        case .authorized:
            return true
        case .fullAccess, .writeOnly:
            if #available(iOS 17.0, *) {
                return true
            } else {
                return false
            }
        default:
            return false
        }
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
        case .fullAccess:
            if #available(iOS 17.0, *) {
                setupCalendar()
                loadReminders()
            } else {
                print("不明な認証状態")
            }
        case .writeOnly:
            if #available(iOS 17.0, *) {
                print("書き込み専用アクセス")
                setupCalendar()
                loadReminders()
            } else {
                print("不明な認証状態")
            }
        @unknown default:
            print("不明な認証状態")
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
        // 保存されたリスト識別子を確認
        let hasSelectedList = UserDefaults.standard.bool(forKey: hasSelectedListKey)
        
        if hasSelectedList {
            // 既に選択されたリストがある場合、それを復元
            if let savedIdentifier = UserDefaults.standard.string(forKey: selectedListIdentifierKey) {
                let calendars = eventStore.calendars(for: .reminder)
                if let savedCalendar = calendars.first(where: { $0.calendarIdentifier == savedIdentifier }) {
                    reminderCalendar = savedCalendar
                    loadReminders()
                    return
                }
            }
        }
        
        // 初回起動または保存されたリストが見つからない場合
        let availableLists = getAvailableReminderLists()
        
        if availableLists.isEmpty {
            // リストが存在しない場合、デフォルトリストを作成
            createDefaultReminderList()
        } else if availableLists.count == 1 {
            // リストが1つしかない場合、それを自動選択
            setSelectedReminderList(availableLists[0])
        } else {
            // 複数のリストがある場合、ユーザーに選択を促す
            needsListSelection = true
        }
    }
    
    private func createDefaultReminderList() {
        // アプリ専用のリマインダーリストを作成
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = "LocationReminder"
        newCalendar.source = eventStore.defaultCalendarForNewReminders()?.source
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            setSelectedReminderList(newCalendar)
        } catch {
            print("リマインダーリストの作成に失敗しました: \(error)")
            // フォールバックとしてデフォルトのリマインダーリストを使用
            if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
                setSelectedReminderList(defaultCalendar)
            }
        }
    }
    
    func loadReminders() {
        guard isAuthorized() else { return }
        
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
        guard isAuthorized(),
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
        guard isAuthorized(),
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
        guard isAuthorized(),
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
        guard isAuthorized(),
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
        guard isAuthorized(),
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
    
    // MARK: - リスト選択関連のメソッド
    
    /// 利用可能なリマインダーリストを取得
    func getAvailableReminderLists() -> [EKCalendar] {
        guard isAuthorized() else {
            return []
        }
        
        return eventStore.calendars(for: .reminder)
    }
    
    /// 選択されたリマインダーリストを設定
    func setSelectedReminderList(_ calendar: EKCalendar) {
        reminderCalendar = calendar
        
        // UserDefaultsに保存
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: selectedListIdentifierKey)
        UserDefaults.standard.set(true, forKey: hasSelectedListKey)
        
        // リスト選択が完了したことを通知
        needsListSelection = false
        
        // タスクを再読み込み
        loadReminders()
    }
    
    /// 現在選択されているリマインダーリストを取得
    func getCurrentReminderList() -> EKCalendar? {
        return reminderCalendar
    }
    
    /// 現在選択されているリスト名を取得
    func getCurrentReminderListName() -> String {
        return reminderCalendar?.title ?? "未選択"
    }
    
    /// リスト選択をリセット（設定変更用）
    func resetListSelection() {
        UserDefaults.standard.removeObject(forKey: selectedListIdentifierKey)
        UserDefaults.standard.set(false, forKey: hasSelectedListKey)
        reminderCalendar = nil
        needsListSelection = true
        tasks = []
        completedTasks = []
    }
}

// 後方互換性のために既存のTaskManagerを残す（段階的移行用）
typealias TaskManager = EventKitTaskManager 