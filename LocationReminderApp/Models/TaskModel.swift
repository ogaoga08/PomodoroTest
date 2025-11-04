import Foundation
import SwiftUI
import EventKit
import CoreLocation
import MapKit

// NotificationCenter用の拡張
extension Notification.Name {
    static let taskUpdated = Notification.Name("taskUpdated")
}

// 位置ベースリマインダーの設定
enum LocationTriggerType: String, CaseIterable, Identifiable, Codable {
    case none = "none"
    case arriving = "arriving"
    case leaving = "leaving"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "なし"
        case .arriving: return "到着時"
        case .leaving: return "出発時"
        }
    }
    
    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .arriving: return "location.fill"
        case .leaving: return "location.slash.fill"
        }
    }
}

// アラーム設定
enum AlarmType: String, CaseIterable, Identifiable, Codable {
    case absoluteTime = "absoluteTime"
    case relativeOffset = "relativeOffset"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .absoluteTime: return "指定時刻"
        case .relativeOffset: return "期限前"
        }
    }
}

struct TaskAlarm: Codable, Equatable, Identifiable {
    var id = UUID()
    var type: AlarmType
    var absoluteDate: Date? // 絶対時刻の場合
    var offsetMinutes: Int? // 相対時間の場合（分単位）
    
    init(type: AlarmType, absoluteDate: Date? = nil, offsetMinutes: Int? = nil) {
        self.type = type
        self.absoluteDate = absoluteDate
        self.offsetMinutes = offsetMinutes
    }
    
    var displayText: String {
        switch type {
        case .absoluteTime:
            if let date = absoluteDate {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
            return "時刻未設定"
        case .relativeOffset:
            if let minutes = offsetMinutes {
                if minutes < 60 {
                    return "\(minutes)分前"
                } else {
                    let hours = minutes / 60
                    let remainingMinutes = minutes % 60
                    if remainingMinutes == 0 {
                        return "\(hours)時間前"
                    } else {
                        return "\(hours)時間\(remainingMinutes)分前"
                    }
                }
            }
            return "時間未設定"
        }
    }
    
    func toEKAlarm(relativeTo dueDate: Date) -> EKAlarm {
        switch type {
        case .absoluteTime:
            if let absoluteDate = absoluteDate {
                return EKAlarm(absoluteDate: absoluteDate)
            } else {
                return EKAlarm(absoluteDate: dueDate)
            }
        case .relativeOffset:
            if let offsetMinutes = offsetMinutes {
                return EKAlarm(relativeOffset: -TimeInterval(offsetMinutes * 60))
            } else {
                return EKAlarm(relativeOffset: 0)
            }
        }
    }
}

struct LocationReminder: Codable, Equatable {
    var title: String
    var address: String
    var latitude: Double
    var longitude: Double
    var radius: Double // メートル単位
    var triggerType: LocationTriggerType
    
    init(title: String = "", address: String = "", latitude: Double = 0, longitude: Double = 0, radius: Double = 100, triggerType: LocationTriggerType = .none) {
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.triggerType = triggerType
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var isValid: Bool {
        return triggerType != .none && !title.isEmpty && latitude != 0 && longitude != 0
    }
}

// 繰り返し設定の列挙型を追加
enum RecurrenceType: String, CaseIterable, Identifiable, Codable {
    case none = "none"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "なし"
        case .daily: return "毎日"
        case .weekly: return "毎週"
        case .monthly: return "毎月"
        case .yearly: return "毎年"
        }
    }
    
    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .daily: return "arrow.clockwise"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .yearly: return "calendar.badge.plus"
        }
    }
    
    // Event Kit用の繰り返しルールを生成
    var ekRecurrenceRule: EKRecurrenceRule? {
        switch self {
        case .none:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }
    
    // Event KitのEKRecurrenceRuleから逆変換
    static func from(recurrenceRule: EKRecurrenceRule?) -> RecurrenceType {
        guard let rule = recurrenceRule else { return .none }
        
        switch rule.frequency {
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        @unknown default:
            return .none
        }
    }
}

// 優先度の列挙型を追加
enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case low = 1
    case medium = 5
    case high = 9
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "なし"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
    
    var color: Color {
        switch self {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .low: return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high: return "exclamationmark.3"
        }
    }
}

struct TaskItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var title: String
    var memo: String
    var dueDate: Date
    var hasTime: Bool = false // 時刻が設定されているかどうか
    var isCompleted: Bool = false
    var completedDate: Date?
    var creationDate: Date? // タスクの作成日時
    var eventKitIdentifier: String? // EventKitのリマインダーIDを保存
    var priority: TaskPriority = .none // 優先度を追加
    var recurrenceType: RecurrenceType = .none // 繰り返し設定を追加
    var locationReminder: LocationReminder = LocationReminder() // 位置ベースリマインダーを追加
    var alarms: [TaskAlarm] = [] // 複数アラームを追加
    var tags: [String] = [] // タグを追加
    var parentId: UUID? = nil // 親タスクのID（サブタスクの場合）
    var isSubtask: Bool = false // サブタスクかどうか
    var subtaskOrder: Int = 0 // サブタスクの順序
    var concentrationLevel: Int? = nil // 集中度合い（1〜5）
    
    // 明示的な初期化子
    init(title: String, memo: String, dueDate: Date, hasTime: Bool = true, priority: TaskPriority = .none, recurrenceType: RecurrenceType = .none, locationReminder: LocationReminder = LocationReminder(), alarms: [TaskAlarm] = [], tags: [String] = [], parentId: UUID? = nil, isSubtask: Bool = false, subtaskOrder: Int = 0) {
        self.title = title
        self.memo = memo
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.recurrenceType = recurrenceType
        self.locationReminder = locationReminder
        self.alarms = alarms
        self.tags = tags
        self.parentId = parentId
        self.isSubtask = isSubtask
        self.subtaskOrder = subtaskOrder
    }
    
    // EventKitのリマインダーから作成するイニシャライザー
    init(from reminder: EKReminder) {
        self.title = reminder.title ?? ""
        self.memo = reminder.notes ?? ""
        self.hasTime = reminder.dueDateComponents?.hour != nil
        self.isCompleted = reminder.isCompleted
        self.completedDate = reminder.completionDate
        self.creationDate = reminder.creationDate
        self.eventKitIdentifier = reminder.calendarItemIdentifier
        
        // 優先度の設定
        self.priority = TaskPriority(rawValue: reminder.priority) ?? .none
        
        // 繰り返し設定の取得
        self.recurrenceType = RecurrenceType.from(recurrenceRule: reminder.recurrenceRules?.first)
        
        // アラームの取得（位置ベースと通常のアラームを分離）
        if let alarms = reminder.alarms {
            var taskAlarms: [TaskAlarm] = []
            
            for alarm in alarms {
                if let structuredLocation = alarm.structuredLocation {
                    // 位置ベースアラームの処理
                    var triggerType: LocationTriggerType = .none
                    if alarm.proximity == .enter {
                        triggerType = .arriving
                    } else if alarm.proximity == .leave {
                        triggerType = .leaving
                    }
                    
                    self.locationReminder = LocationReminder(
                        title: structuredLocation.title ?? "",
                        address: structuredLocation.title ?? "",
                        latitude: structuredLocation.geoLocation?.coordinate.latitude ?? 0,
                        longitude: structuredLocation.geoLocation?.coordinate.longitude ?? 0,
                        radius: structuredLocation.radius,
                        triggerType: triggerType
                    )
                } else {
                    // 通常のアラームの処理
                    if let absoluteDate = alarm.absoluteDate {
                        taskAlarms.append(TaskAlarm(type: .absoluteTime, absoluteDate: absoluteDate))
                    } else if alarm.relativeOffset != 0 {
                        let offsetMinutes = Int(-alarm.relativeOffset / 60)
                        taskAlarms.append(TaskAlarm(type: .relativeOffset, offsetMinutes: offsetMinutes))
                    }
                }
            }
            
            self.alarms = taskAlarms
        }
        
        // 期限日の設定
        if let dueDateComponents = reminder.dueDateComponents {
            let calendar = Calendar.current
            self.dueDate = calendar.date(from: dueDateComponents) ?? Date()
        } else {
            self.dueDate = Date()
        }
        
        // サブタスク情報の抽出（メモから）
        let memoAndTags = TaskItem.extractMemoAndTags(from: self.memo)
        let (cleanMemo, concentration) = TaskItem.extractConcentrationLevel(from: memoAndTags.memo)
        let subtaskInfo = TaskItem.extractSubtaskInfo(from: cleanMemo)
        self.memo = subtaskInfo.memo
        self.parentId = subtaskInfo.parentId
        self.isSubtask = subtaskInfo.isSubtask
        self.subtaskOrder = subtaskInfo.subtaskOrder
        self.concentrationLevel = concentration
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
    
    // タグを含まないメモテキストを取得
    var cleanMemo: String {
        return TaskItem.extractMemoAndTags(from: memo).memo
    }
    
    // メモとタグの結合文字列を生成（Event Kit保存用）
    var memoWithTags: String {
        var result = memo
        if !tags.isEmpty {
            let tagString = tags.map { "#\($0)" }.joined(separator: " ")
            if !result.isEmpty {
                result += "\n\n[tags: \(tagString)]"
            } else {
                result = "[tags: \(tagString)]"
            }
        }
        return result
    }
    
    // メモ文字列からメモとタグを抽出
    static func extractMemoAndTags(from memoText: String) -> (memo: String, tags: [String]) {
        let pattern = #"\[tags: (.+?)\]"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(memoText.startIndex..<memoText.endIndex, in: memoText)
        
        if let match = regex.firstMatch(in: memoText, options: [], range: range) {
            let tagRange = Range(match.range(at: 1), in: memoText)!
            let tagString = String(memoText[tagRange])
            let tags = tagString.components(separatedBy: " ").compactMap { tagText in
                if tagText.hasPrefix("#") {
                    return String(tagText.dropFirst())
                }
                return nil
            }
            
            let fullMatchRange = Range(match.range, in: memoText)!
            let memoWithoutTags = memoText.replacingCharacters(in: fullMatchRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (memoWithoutTags, tags)
        }
        
        return (memoText, [])
    }
    
    // サブタスク情報をメモから抽出
    static func extractSubtaskInfo(from memoText: String) -> (memo: String, parentId: UUID?, isSubtask: Bool, subtaskOrder: Int) {
        let pattern = #"\[subtask: parentId=([^,]+), order=(\d+)\]"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(memoText.startIndex..<memoText.endIndex, in: memoText)
        
        if let match = regex.firstMatch(in: memoText, options: [], range: range) {
            let parentIdRange = Range(match.range(at: 1), in: memoText)!
            let orderRange = Range(match.range(at: 2), in: memoText)!
            
            let parentIdString = String(memoText[parentIdRange])
            let orderString = String(memoText[orderRange])
            
            let fullMatchRange = Range(match.range, in: memoText)!
            let memoWithoutSubtask = memoText.replacingCharacters(in: fullMatchRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let parentId = UUID(uuidString: parentIdString), let order = Int(orderString) {
                return (memoWithoutSubtask, parentId, true, order)
            }
        }
        
        return (memoText, nil, false, 0)
    }
    
    // 集中度合いをメモから抽出
    static func extractConcentrationLevel(from memoText: String) -> (memo: String, concentrationLevel: Int?) {
        let pattern = #"\[concentration: (\d+)\]"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(memoText.startIndex..<memoText.endIndex, in: memoText)
        
        if let match = regex.firstMatch(in: memoText, options: [], range: range) {
            let levelRange = Range(match.range(at: 1), in: memoText)!
            let levelString = String(memoText[levelRange])
            
            let fullMatchRange = Range(match.range, in: memoText)!
            let memoWithoutConcentration = memoText.replacingCharacters(in: fullMatchRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let level = Int(levelString), level >= 1 && level <= 5 {
                return (memoWithoutConcentration, level)
            }
        }
        
        return (memoText, nil)
    }
    
    // サブタスク情報を含むメモを生成（EventKit保存用）
    var memoWithSubtaskInfo: String {
        var result = memoWithTags
        
        if isSubtask, let parentId = parentId {
            let subtaskString = "[subtask: parentId=\(parentId.uuidString), order=\(subtaskOrder)]"
            if !result.isEmpty {
                result += "\n\(subtaskString)"
            } else {
                result = subtaskString
            }
        }
        
        return result
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
    private let hasCreatedInitialTasksKey = "HasCreatedInitialTasks"
    
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
            // 自動リクエストはしない（オンボーディングで処理）
            print("リマインダーアクセスが未確認です")
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
    
    // PermissionManager用のパブリックメソッド
    func requestReminderAccess() {
        requestAccess()
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
        reminder.title = task.isSubtask ? "└ \(task.title)" : task.title
        reminder.notes = task.memoWithSubtaskInfo
        reminder.calendar = calendar
        reminder.priority = task.priority.rawValue // 優先度を設定
        
        // 繰り返し設定の適用
        if let recurrenceRule = task.recurrenceType.ekRecurrenceRule {
            reminder.recurrenceRules = [recurrenceRule]
        }
        
        // 期限日の設定
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: task.dueDate)
        if !task.hasTime {
            // 時刻が設定されていない場合、時刻コンポーネントをクリア
            components.hour = nil
            components.minute = nil
        }
        reminder.dueDateComponents = components
        
        // 複数アラームの設定
        if !task.alarms.isEmpty {
            for taskAlarm in task.alarms {
                let ekAlarm = taskAlarm.toEKAlarm(relativeTo: task.dueDate)
                reminder.addAlarm(ekAlarm)
            }
        } else {
            // アラームが設定されていない場合、デフォルトアラームを設定
            if task.hasTime {
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
        }
        
        // 位置ベースアラームの設定
        if task.locationReminder.isValid {
            let location = CLLocation(latitude: task.locationReminder.latitude, longitude: task.locationReminder.longitude)
            let structuredLocation = EKStructuredLocation(title: task.locationReminder.title)
            structuredLocation.geoLocation = location
            structuredLocation.radius = task.locationReminder.radius
            
            let locationAlarm = EKAlarm()
            locationAlarm.structuredLocation = structuredLocation
            
            switch task.locationReminder.triggerType {
            case .arriving:
                locationAlarm.proximity = .enter
            case .leaving:
                locationAlarm.proximity = .leave
            case .none:
                break // 位置アラームを設定しない
            }
            
            if task.locationReminder.triggerType != .none {
                reminder.addAlarm(locationAlarm)
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders() // リマインダーを再読み込み
            
            // タスク追加後にScreen Time制限を再評価
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .taskUpdated, object: nil)
            }
        } catch {
            print("リマインダーの保存に失敗しました: \(error)")
        }
    }
    
    func updateTask(_ task: TaskItem) {
        guard isAuthorized(),
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            print("⚠️ リマインダーの更新に失敗: eventKitIdentifier=\(task.eventKitIdentifier ?? "nil")")
            return
        }
        
        print("📝 リマインダーを更新: \(task.title), 期限: \(task.dueDate)")
        print("   - 更新前の期限: \(reminder.dueDateComponents?.date ?? Date())")
        
        reminder.title = task.isSubtask ? "└ \(task.title)" : task.title
        reminder.notes = task.memoWithSubtaskInfo
        reminder.priority = task.priority.rawValue // 優先度を更新
        
        // 繰り返し設定の更新
        reminder.recurrenceRules = nil // 既存のルールをクリア
        if let recurrenceRule = task.recurrenceType.ekRecurrenceRule {
            reminder.recurrenceRules = [recurrenceRule]
        }
        
        // 既存のアラームを削除
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        
        // 期限日の更新
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: task.dueDate)
        if !task.hasTime {
            // 時刻が設定されていない場合、時刻コンポーネントをクリア
            components.hour = nil
            components.minute = nil
        }
        reminder.dueDateComponents = components
        
        print("   - 更新後の期限: \(reminder.dueDateComponents?.date ?? Date())")
        print("   - hasTime: \(task.hasTime), components: year=\(components.year ?? 0), month=\(components.month ?? 0), day=\(components.day ?? 0), hour=\(components.hour ?? -1), minute=\(components.minute ?? -1), timeZone=\(components.timeZone?.identifier ?? "nil")")
        
        // 複数アラームの設定
        if !task.alarms.isEmpty {
            for taskAlarm in task.alarms {
                let ekAlarm = taskAlarm.toEKAlarm(relativeTo: task.dueDate)
                reminder.addAlarm(ekAlarm)
            }
        } else {
            // アラームが設定されていない場合、デフォルトアラームを設定
            if task.hasTime {
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
        }
        
        // 位置ベースアラームの設定
        if task.locationReminder.isValid {
            let location = CLLocation(latitude: task.locationReminder.latitude, longitude: task.locationReminder.longitude)
            let structuredLocation = EKStructuredLocation(title: task.locationReminder.title)
            structuredLocation.geoLocation = location
            structuredLocation.radius = task.locationReminder.radius
            
            let locationAlarm = EKAlarm()
            locationAlarm.structuredLocation = structuredLocation
            
            switch task.locationReminder.triggerType {
            case .arriving:
                locationAlarm.proximity = .enter
            case .leaving:
                locationAlarm.proximity = .leave
            case .none:
                break // 位置アラームを設定しない
            }
            
            if task.locationReminder.triggerType != .none {
                reminder.addAlarm(locationAlarm)
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ リマインダーの更新に成功: \(task.title)")
            
            // ローカルのタスク配列も即座に更新（UI反映を高速化）
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
                print("📱 ローカルタスク配列を更新: インデックス \(index)")
            } else if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
                completedTasks[index] = task
                print("📱 完了済みタスク配列を更新: インデックス \(index)")
            }
            
            // EventKitから最新のデータを取得（非同期で更新）
            loadReminders()
            
            // タスク更新後にScreen Time制限を再評価
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .taskUpdated, object: nil)
            }
        } catch {
            print("❌ リマインダーの更新に失敗しました: \(error)")
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
    
    func completeTask(_ task: TaskItem, concentrationLevel: Int? = nil) {
        guard isAuthorized(),
              let identifier = task.eventKitIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        
        reminder.isCompleted = true
        reminder.completionDate = Date()
        
        // 集中度合いをメモに保存
        if let level = concentrationLevel {
            var updatedTask = task
            updatedTask.concentrationLevel = level
            
            // メモに集中度合いを追加
            let concentrationTag = "[concentration: \(level)]"
            if reminder.notes?.contains("[concentration:") == true {
                // 既存の集中度合いタグを置換
                let pattern = #"\[concentration: \d+\]"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(reminder.notes!.startIndex..<reminder.notes!.endIndex, in: reminder.notes!)
                    reminder.notes = regex.stringByReplacingMatches(
                        in: reminder.notes!,
                        range: range,
                        withTemplate: concentrationTag
                    )
                }
            } else {
                // 新規に集中度合いタグを追加
                if let notes = reminder.notes, !notes.isEmpty {
                    reminder.notes = "\(notes)\n\(concentrationTag)"
                } else {
                    reminder.notes = concentrationTag
                }
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders()
            
            // タスク完了時に今日のスナップショットを更新（今日のみ）
            updateTodaySnapshot()
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
            
            // タスク未完了時に今日のスナップショットを更新（今日のみ）
            updateTodaySnapshot()
        } catch {
            print("リマインダーの未完了処理に失敗しました: \(error)")
        }
    }
    
    // MARK: - サブタスク管理機能
    
    /// 指定された親タスクにサブタスクを追加
    func addSubtask(to parentTask: TaskItem, title: String, memo: String = "", dueDate: Date? = nil, priority: TaskPriority = .none) {
        guard isAuthorized(),
              let calendar = reminderCalendar else { return }
        
        // サブタスクの順序を決定（既存のサブタスクの数 + 1）
        let existingSubtasks = getSubtasks(for: parentTask)
        let newOrder = existingSubtasks.count + 1
        
        // サブタスクの期限日は親タスクの期限日を基本とする
        let subtaskDueDate = dueDate ?? parentTask.dueDate
        
        let subtask = TaskItem(
            title: title,
            memo: memo,
            dueDate: subtaskDueDate,
            hasTime: parentTask.hasTime,
            priority: priority,
            parentId: parentTask.id,
            isSubtask: true,
            subtaskOrder: newOrder
        )
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "└ \(subtask.title)" // インデントを表現
        reminder.notes = subtask.memoWithSubtaskInfo
        reminder.calendar = calendar
        reminder.priority = subtask.priority.rawValue
        
        // 期限日の設定
        var components = Calendar.current.dateComponents([.year, .month, .day], from: subtask.dueDate)
        if subtask.hasTime {
            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: subtask.dueDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
        }
        reminder.dueDateComponents = components
        
        // デフォルトアラームの設定
        if subtask.hasTime {
            let alarm = EKAlarm(absoluteDate: subtask.dueDate)
            reminder.addAlarm(alarm)
        } else {
            var alarmComponents = components
            alarmComponents.hour = 9
            alarmComponents.minute = 0
            if let alarmDate = Calendar.current.date(from: alarmComponents) {
                let alarm = EKAlarm(absoluteDate: alarmDate)
                reminder.addAlarm(alarm)
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            loadReminders()
            
            // サブタスク追加後にScreen Time制限を再評価
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .taskUpdated, object: nil)
            }
        } catch {
            print("サブタスクの保存に失敗しました: \(error)")
        }
    }
    
    /// 特定の親タスクのサブタスクを取得
    func getSubtasks(for parentTask: TaskItem) -> [TaskItem] {
        let allTasks = tasks + completedTasks
        return allTasks.filter { $0.parentId == parentTask.id }
            .sorted { $0.subtaskOrder < $1.subtaskOrder }
    }
    
    /// 親タスクのみを取得（サブタスクを除外）
    func getParentTasks() -> [TaskItem] {
        return tasks.filter { !$0.isSubtask }
    }
    
    /// 完了済みの親タスクのみを取得
    func getCompletedParentTasks() -> [TaskItem] {
        return completedTasks.filter { !$0.isSubtask }
    }
    
    /// サブタスクを削除（親タスクが削除される場合、そのサブタスクも削除）
    func deleteSubtask(_ subtask: TaskItem) {
        guard subtask.isSubtask else {
            // 親タスクの場合、すべてのサブタスクも削除
            let subtasks = getSubtasks(for: subtask)
            for childSubtask in subtasks {
                deleteTask(childSubtask)
            }
            deleteTask(subtask)
            return
        }
        
        deleteTask(subtask)
        
        // サブタスクの順序を再調整
        if let parentId = subtask.parentId,
           let parentTask = (tasks + completedTasks).first(where: { $0.id == parentId }) {
            reorderSubtasks(for: parentTask)
        }
    }
    
    /// サブタスクの順序を再調整
    private func reorderSubtasks(for parentTask: TaskItem) {
        let subtasks = getSubtasks(for: parentTask)
        
        for (index, subtask) in subtasks.enumerated() {
            if subtask.subtaskOrder != index + 1 {
                var updatedSubtask = subtask
                updatedSubtask.subtaskOrder = index + 1
                updateTask(updatedSubtask)
            }
        }
    }
    
    /// サブタスクを完了（親タスクの完了状況も確認）
    func completeSubtask(_ subtask: TaskItem) {
        guard subtask.isSubtask else {
            completeTask(subtask)
            return
        }
        
        completeTask(subtask)
        
        // 親タスクのすべてのサブタスクが完了しているかチェック
        if let parentId = subtask.parentId,
           let parentTask = tasks.first(where: { $0.id == parentId }) {
            checkParentTaskCompletion(parentTask)
        }
    }
    
    /// 親タスクの完了状況をチェック（すべてのサブタスクが完了していれば親タスクも完了）
    private func checkParentTaskCompletion(_ parentTask: TaskItem) {
        let allSubtasks = getSubtasks(for: parentTask)
        let incompleteSubtasks = allSubtasks.filter { !$0.isCompleted }
        
        // すべてのサブタスクが完了している場合、親タスクも完了
        if incompleteSubtasks.isEmpty && !allSubtasks.isEmpty {
            completeTask(parentTask)
        }
    }
    
    /// サブタスクを未完了に戻す
    func uncompleteSubtask(_ subtask: TaskItem) {
        uncompleteTask(subtask)
        
        // 親タスクが完了している場合、未完了に戻す
        if let parentId = subtask.parentId,
           let parentTask = completedTasks.first(where: { $0.id == parentId && $0.isCompleted }) {
            uncompleteTask(parentTask)
        }
    }
    
    /// タスクの進捗率を取得（サブタスクを考慮）
    func getTaskProgress(_ task: TaskItem) -> Double {
        if task.isSubtask {
            return task.isCompleted ? 1.0 : 0.0
        }
        
        let subtasks = getSubtasks(for: task)
        if subtasks.isEmpty {
            return task.isCompleted ? 1.0 : 0.0
        }
        
        let completedSubtasks = subtasks.filter { $0.isCompleted }
        return Double(completedSubtasks.count) / Double(subtasks.count)
    }
    
    /// 親タスクのサブタスク完了数/総数を取得
    func getSubtaskProgress(_ parentTask: TaskItem) -> (completed: Int, total: Int) {
        let subtasks = getSubtasks(for: parentTask)
        let completed = subtasks.filter { $0.isCompleted }.count
        return (completed: completed, total: subtasks.count)
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
    
    /// 新規リマインダーリストを作成
    func createNewReminderList(named title: String) throws -> EKCalendar {
        guard isAuthorized() else {
            throw NSError(domain: "TaskManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "リマインダーアクセスの認証が必要です"])
        }
        
        // 新しいリマインダーリストを作成
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = title
        newCalendar.source = eventStore.defaultCalendarForNewReminders()?.source
        
        // EventStoreに保存
        try eventStore.saveCalendar(newCalendar, commit: true)
        
        print("新しいリマインダーリスト「\(title)」を作成しました")
        return newCalendar
    }
    
    // MARK: - 統計・分析機能
    
    /// 基本統計情報
    struct TaskStatistics {
        let totalTasks: Int
        let completedTasks: Int
        let pendingTasks: Int
        let overdueTasks: Int
        let completionRate: Double
        let overdueRate: Double
        
        // 今日のタスク統計
        let todayTasks: Int
        let todayCompleted: Int
        let todayOverdue: Int
        
        // 優先度別統計
        let highPriorityTasks: Int
        let mediumPriorityTasks: Int
        let lowPriorityTasks: Int
        
        // 今週の統計
        let weeklyCompleted: Int
        let weeklyCreated: Int
        
        // 今月の統計
        let monthlyCompleted: Int
        let monthlyCreated: Int
        
        // 新しい統計項目
        let averageInRoomTime: TimeInterval // 平均在室時間（秒）
        let totalOutsideTime: TimeInterval // 不在時間（秒）
        let breakCount: Int // 休憩回数
    }
    
    /// 週別統計データ
    struct WeeklyStats {
        let weekStart: Date
        let completed: Int
        let created: Int
        let overdue: Int
    }
    
    /// 月別統計データ
    struct MonthlyStats {
        let month: Date
        let completed: Int
        let created: Int
        let overdue: Int
    }
    
    /// 詳細統計情報を取得
    func getDetailedStatistics() -> TaskStatistics {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
        
        let allTasks = tasks + completedTasks
        let totalTasks = allTasks.count
        let completedCount = completedTasks.count
        let pendingCount = tasks.count
        
        // 期限超過タスクの計算
        let overdueCount = tasks.filter { task in
            task.dueDate < today
        }.count
        
        // 今日のタスク統計
        let todayTasks = tasks.filter { task in
            calendar.isDate(task.dueDate, inSameDayAs: today)
        }.count
        
        let todayCompleted = completedTasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return calendar.isDate(completedDate, inSameDayAs: today)
        }.count
        
        let todayOverdue = tasks.filter { task in
            task.dueDate < today && calendar.isDate(task.dueDate, inSameDayAs: today)
        }.count
        
        // 優先度別統計
        let highPriorityCount = allTasks.filter { $0.priority == .high }.count
        let mediumPriorityCount = allTasks.filter { $0.priority == .medium }.count
        let lowPriorityCount = allTasks.filter { $0.priority == .low }.count
        
        // 今週の統計
        let weeklyCompleted = completedTasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return completedDate >= weekStart
        }.count
        
        let weeklyCreated = allTasks.filter { task in
            // 作成日がない場合は期限日を参考にする
            task.dueDate >= weekStart
        }.count
        
        // 今月の統計
        let monthlyCompleted = completedTasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return completedDate >= monthStart
        }.count
        
        let monthlyCreated = allTasks.filter { task in
            task.dueDate >= monthStart
        }.count
        
        // 新しい統計項目を計算
        let (averageInRoomTime, totalOutsideTime, breakCount) = calculateTimeStatistics()
        
        return TaskStatistics(
            totalTasks: totalTasks,
            completedTasks: completedCount,
            pendingTasks: pendingCount,
            overdueTasks: overdueCount,
            completionRate: totalTasks > 0 ? Double(completedCount) / Double(totalTasks) : 0.0,
            overdueRate: pendingCount > 0 ? Double(overdueCount) / Double(pendingCount) : 0.0,
            todayTasks: todayTasks,
            todayCompleted: todayCompleted,
            todayOverdue: todayOverdue,
            highPriorityTasks: highPriorityCount,
            mediumPriorityTasks: mediumPriorityCount,
            lowPriorityTasks: lowPriorityCount,
            weeklyCompleted: weeklyCompleted,
            weeklyCreated: weeklyCreated,
            monthlyCompleted: monthlyCompleted,
            monthlyCreated: monthlyCreated,
            averageInRoomTime: averageInRoomTime,
            totalOutsideTime: totalOutsideTime,
            breakCount: breakCount
        )
    }
    
    /// 時間関連の統計を計算
    private func calculateTimeStatistics() -> (averageInRoomTime: TimeInterval, totalOutsideTime: TimeInterval, breakCount: Int) {
        // 実際のデータを取得
        let averageInRoomTime = getAverageInRoomTimeFromManagers()
        let totalOutsideTime = getTotalOutsideTimeFromManagers()
        let breakCount = getBreakCountFromManagers()
        
        return (averageInRoomTime, totalOutsideTime, breakCount)
    }
    
    /// ScreenTimeManagerから平均在室時間を取得
    private func getAverageInRoomTimeFromManagers() -> TimeInterval {
        // ScreenTimeManagerのインスタンスを取得する方法を実装
        // 現在はUserDefaultsから直接データを読み取る
        let userDefaults = UserDefaults.standard
        let restrictionSessionsKey = "screen_time_restriction_sessions"
        
        guard let data = userDefaults.data(forKey: restrictionSessionsKey),
              let sessions = try? JSONDecoder().decode([RestrictionSession].self, from: data) else {
            return 0
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let todaySessions = sessions.filter { Calendar.current.isDate($0.startTime, inSameDayAs: today) }
        
        guard !todaySessions.isEmpty else { return 0 }
        
        let totalTime = todaySessions.reduce(0) { $0 + $1.duration }
        return totalTime / Double(todaySessions.count)
    }
    
    /// UWBManagerから不在時間を取得
    private func getTotalOutsideTimeFromManagers() -> TimeInterval {
        // UWBManagerのデータをUserDefaultsから直接読み取る
        let userDefaults = UserDefaults.standard
        let bubbleSessionsKey = "uwb_bubble_sessions"
        
        guard let data = userDefaults.data(forKey: bubbleSessionsKey),
              let sessions = try? JSONDecoder().decode([BubbleSession].self, from: data) else {
            return 0
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayOutsideSessions = sessions.filter { 
            $0.isOutside && Calendar.current.isDate($0.startTime, inSameDayAs: today)
        }
        
        return todayOutsideSessions.reduce(0) { $0 + $1.duration }
    }
    
    /// UWBManagerから休憩回数を取得
    private func getBreakCountFromManagers() -> Int {
        // UWBManagerのデータをUserDefaultsから直接読み取る
        let userDefaults = UserDefaults.standard
        let bubbleSessionsKey = "uwb_bubble_sessions"
        
        guard let data = userDefaults.data(forKey: bubbleSessionsKey),
              let sessions = try? JSONDecoder().decode([BubbleSession].self, from: data) else {
            return 0
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayOutsideSessions = sessions.filter { 
            $0.isOutside && calendar.isDate($0.startTime, inSameDayAs: today)
        }
        
        return todayOutsideSessions.count
    }
    
    // 統計データ構造の定義（ScreenTimeManagerとUWBManagerと同じ構造）
    private struct RestrictionSession: Codable {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let taskId: String?
    }
    
    private struct BubbleSession: Codable {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let isOutside: Bool
        let taskId: String?
    }
    
    /// 過去数週間の週別統計を取得
    func getWeeklyStatistics(weeksBack: Int = 8) -> [WeeklyStats] {
        let calendar = Calendar.current
        let now = Date()
        var stats: [WeeklyStats] = []
        
        for weekOffset in 0..<weeksBack {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }
            
            let weekEnd = weekInterval.end
            
            let weekCompleted = completedTasks.filter { task in
                guard let completedDate = task.completedDate else { return false }
                return completedDate >= weekInterval.start && completedDate < weekEnd
            }.count
            
            let weekCreated = (tasks + completedTasks).filter { task in
                return task.dueDate >= weekInterval.start && task.dueDate < weekEnd
            }.count
            
            let weekOverdue = tasks.filter { task in
                return task.dueDate >= weekInterval.start && task.dueDate < weekEnd && task.dueDate < calendar.startOfDay(for: now)
            }.count
            
            stats.append(WeeklyStats(
                weekStart: weekInterval.start,
                completed: weekCompleted,
                created: weekCreated,
                overdue: weekOverdue
            ))
        }
        
        return stats.reversed() // 古い順にソート
    }
    
    // MARK: - 初期タスク管理
    
    /// 初期タスクが作成済みかどうかを確認
    func hasCreatedInitialTasks() -> Bool {
        return UserDefaults.standard.bool(forKey: hasCreatedInitialTasksKey)
    }
    
    /// 初期タスク作成済みフラグを設定
    func setInitialTasksCreated() {
        UserDefaults.standard.set(true, forKey: hasCreatedInitialTasksKey)
    }
    
    /// 「実験用リスト」を作成し、選択する
    func createExperimentalReminderList() throws -> EKCalendar {
        guard isAuthorized() else {
            throw NSError(domain: "TaskManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "リマインダーアクセスの認証が必要です"])
        }
        
        // 新しいリマインダーリストを作成
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = "実験用リスト"
        newCalendar.source = eventStore.defaultCalendarForNewReminders()?.source
        
        // EventStoreに保存
        try eventStore.saveCalendar(newCalendar, commit: true)
        
        // このリストを選択
        setSelectedReminderList(newCalendar)
        
        print("「実験用リスト」を作成しました")
        return newCalendar
    }
    
    /// 初期タスクを一括登録
    /// - Parameter startDate: 1日目の日付
    func createInitialTasks(from startDate: Date) {
        guard isAuthorized(),
              reminderCalendar != nil else {
            print("初期タスクの作成に失敗: 認証またはリストが未設定")
            return
        }
        
        // 初期タスクを生成
        let initialTasksData = InitialTaskGenerator.generateInitialTasks(from: startDate)
        
        print("初期タスクを\(initialTasksData.count)件作成します...")
        
        // 各タスクをEventKitに登録
        for taskData in initialTasksData {
            let task = taskData.toTaskItem()
            addTask(task)
        }
        
        // 初期タスク作成済みフラグを立てる
        setInitialTasksCreated()
        
        print("初期タスクの作成が完了しました")
    }
    
    // MARK: - 自宅位置情報タスク管理（UWB自動ペアリング用）
    
    /// 自宅位置情報タスクを作成または更新する（UWB自動ペアリング用）
    /// - Parameters:
    ///   - coordinate: 自宅の座標
    ///   - address: 自宅の住所
    ///   - radius: ジオフェンスの半径（メートル）
    func createOrUpdateHomeLocationTask(
        coordinate: CLLocationCoordinate2D,
        address: String,
        radius: Double = 50.0
    ) {
        guard isAuthorized(),
              reminderCalendar != nil else {
            print("❌ 自宅タスクの作成に失敗: 認証またはリストが未設定")
            return
        }
        
        print("🏠 自宅位置情報タスクを作成/更新します")
        print("   - 住所: \(address)")
        print("   - 座標: (\(coordinate.latitude), \(coordinate.longitude))")
        print("   - 半径: \(radius)m")
        
        // 既存の自宅タスクを検索
        let existingHomeTask = tasks.first { task in
            task.title.contains("自宅（UWB自動接続用）") ||
            task.memo.contains("[uwb_auto_trigger]")
        }
        
        if let existingTask = existingHomeTask {
            // 既存のタスクを更新
            print("✏️ 既存の自宅タスクを更新: \(existingTask.title)")
            
            var updatedTask = existingTask
            updatedTask.locationReminder = LocationReminder(
                title: address,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: radius,
                triggerType: .arriving // 到着時にトリガー
            )
            updatedTask.memo = "[uwb_auto_trigger] 自宅に到着するとUWBデバイスとの自動接続が開始されます"
            
            updateTask(updatedTask)
            print("✅ 自宅タスク更新完了")
            
        } else {
            // 新規タスクを作成
            print("📝 新規自宅タスクを作成")
            
            let homeTask = TaskItem(
                title: "自宅（UWB自動接続用）",
                memo: "[uwb_auto_trigger] 自宅に到着するとUWBデバイスとの自動接続が開始されます",
                dueDate: Date().addingTimeInterval(86400 * 365), // 1年後（期限を遠くに設定）
                hasTime: false,
                priority: .none,
                recurrenceType: .none,
                locationReminder: LocationReminder(
                    title: address,
                    address: address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radius: radius,
                    triggerType: .arriving // 到着時にトリガー
                ),
                alarms: [], // 位置アラームのみ使用
                tags: ["uwb", "自宅"],
                parentId: nil,
                isSubtask: false,
                subtaskOrder: 0
            )
            
            addTask(homeTask)
            print("✅ 自宅タスク作成完了")
        }
    }
    
    /// 自宅位置情報タスクを削除する
    func deleteHomeLocationTask() {
        let homeTask = tasks.first { task in
            task.title.contains("自宅（UWB自動接続用）") ||
            task.memo.contains("[uwb_auto_trigger]")
        }
        
        if let task = homeTask {
            print("🗑️ 自宅タスクを削除: \(task.title)")
            deleteTask(task)
            print("✅ 自宅タスク削除完了")
        } else {
            print("ℹ️ 削除する自宅タスクが見つかりませんでした")
        }
    }
    
    /// 過去数ヶ月の月別統計を取得
    func getMonthlyStatistics(monthsBack: Int = 6) -> [MonthlyStats] {
        let calendar = Calendar.current
        let now = Date()
        var stats: [MonthlyStats] = []
        
        for monthOffset in 0..<monthsBack {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: now),
                  let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { continue }
            
            let monthEnd = monthInterval.end
            
            let monthCompleted = completedTasks.filter { task in
                guard let completedDate = task.completedDate else { return false }
                return completedDate >= monthInterval.start && completedDate < monthEnd
            }.count
            
            let monthCreated = (tasks + completedTasks).filter { task in
                return task.dueDate >= monthInterval.start && task.dueDate < monthEnd
            }.count
            
            let monthOverdue = tasks.filter { task in
                return task.dueDate >= monthInterval.start && task.dueDate < monthEnd && task.dueDate < calendar.startOfDay(for: now)
            }.count
            
            stats.append(MonthlyStats(
                month: monthInterval.start,
                completed: monthCompleted,
                created: monthCreated,
                overdue: monthOverdue
            ))
        }
        
        return stats.reversed() // 古い順にソート
    }
    
    // MARK: - スナップショット管理
    
    /// 今日のタスク完了数スナップショットを更新（今日のみ）
    private func updateTodaySnapshot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 今日完了したタスクの数を取得
        let todayCompletedCount = completedTasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return calendar.isDate(completedDate, inSameDayAs: today)
        }.count
        
        // スナップショットを更新（今日のみ）
        TaskSnapshotHelper.upsertSnapshot(for: today, completedCount: todayCompletedCount)
        
        print("📸 今日のスナップショット更新: \(todayCompletedCount)件")
    }
}

// 日別スナップショットヘルパー（TaskModel用）
fileprivate struct TaskDailySnapshot: Codable {
    let date: Date
    let completedCount: Int
}

fileprivate struct TaskSnapshotHelper {
    private static let key = "daily_stats_snapshots"
    
    static func upsertSnapshot(for date: Date, completedCount: Int) {
        var all = loadAll()
        let calendar = Calendar.current
        if let idx = all.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            all[idx] = TaskDailySnapshot(date: calendar.startOfDay(for: date), completedCount: completedCount)
        } else {
            all.append(TaskDailySnapshot(date: calendar.startOfDay(for: date), completedCount: completedCount))
        }
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        all = all.filter { $0.date >= ninetyDaysAgo }
        saveAll(all)
    }
    
    private static func loadAll() -> [TaskDailySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TaskDailySnapshot].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private static func saveAll(_ snapshots: [TaskDailySnapshot]) {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 初期タスク生成

/// 初期タスクの種類
enum InitialTaskType: String, CaseIterable {
    case vocabulary = "英単語課題"
    case generalKnowledge = "一般教養課題"
    case videoWatching = "動画視聴課題"
    
    var displayName: String {
        return rawValue
    }
}

/// 初期タスクのデータ
struct InitialTaskData {
    let type: InitialTaskType
    let dayNumber: Int
    let title: String
    let memo: String
    let dueDate: Date
    
    /// 初期タスクからTaskItemを生成
    func toTaskItem() -> TaskItem {
        return TaskItem(
            title: title,
            memo: memo,
            dueDate: dueDate,
            hasTime: true,
            priority: .none,
            recurrenceType: .none
        )
    }
}

/// 初期タスク生成ユーティリティ
struct InitialTaskGenerator {
    /// 開始日から初期タスクを生成
    /// - Parameter startDate: 1日目の日付
    /// - Returns: 生成された初期タスクの配列
    static func generateInitialTasks(from startDate: Date) -> [InitialTaskData] {
        var tasks: [InitialTaskData] = []
        let calendar = Calendar.current
        
        // 1日目から14日目まで繰り返し
        for day in 1...14 {
            // その日の17:00の日付を作成
            guard let targetDate = calendar.date(byAdding: .day, value: day - 1, to: startDate) else {
                continue
            }
            
            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = 17
            components.minute = 0
            components.second = 0
            
            guard let taskDate = calendar.date(from: components) else {
                continue
            }
            
            // 英単語課題（日ごとに異なるURL）
            tasks.append(InitialTaskData(
                type: .vocabulary,
                dayNumber: day,
                title: "英単語課題\(day)日目",
                memo: getVocabularyURL(for: day),
                dueDate: taskDate
            ))
            
            // IT課題（日ごとに異なるURL）
            tasks.append(InitialTaskData(
                type: .generalKnowledge,
                dayNumber: day,
                title: "ITパスポート課題\(day)日目",
                memo: getGeneralKnowledgeURL(for: day),
                dueDate: taskDate
            ))
            
            // 動画視聴課題（4日目と11日目のみ）
            if day == 4 || day == 11 {
                tasks.append(InitialTaskData(
                    type: .videoWatching,
                    dayNumber: day,
                    title: "動画視聴課題",
                    memo: getVideoWatchingURL(for: day),
                    dueDate: taskDate
                ))
            }
        }
        
        return tasks
    }
    
    // MARK: - URL生成メソッド（ここを編集して実際のURLを設定してください）
    
    /// 英単語課題のURLを取得
    /// - Parameter day: 日数（1〜14）
    /// - Returns: Google FormのURL
    private static func getVocabularyURL(for day: Int) -> String {
        // ここに実際のGoogle FormのURLを日ごとに設定してください
        // 例: 
        switch day {
        case 1: return "https://forms.gle/9ExUG7V9f5iKNXpp9"
        case 2: return "https://forms.gle/CUrAbAT9R8Zh8gMy8"
        case 3: return "https://forms.gle/VMAAx2w5EW9qi1sj6"
        case 4: return "https://forms.gle/WEKu5SNaK87eziEL8"
        case 5: return "https://forms.gle/KEwgZzvgngWRLxGw8"
        case 6: return "https://forms.gle/airgiAZWsLv8e2nM7"
        case 7: return "https://forms.gle/4t1SQpd6iD1bBAcq5"
        case 8: return "https://forms.gle/rUB4nA41j8xr8h3Y7"
        case 9: return "https://forms.gle/tCKz3Xia9NfJF5996"
        case 10: return "https://forms.gle/9pZiJ8UNWCLjC76g7"
        case 11: return "https://forms.gle/p7aqbwTKDj8Uutsu6"
        case 12: return "https://forms.gle/oAYFWEynPWRrmT3A8"
        case 13: return "https://forms.gle/KCoHLKmaKj99xFZM6"
        case 14: return "https://forms.gle/U6CkeaGNUH8ueGEa7"
        
        default: return ""
        }
        
    }
    
    /// IT課題のURLを取得
    /// - Parameter day: 日数（1〜14）
    /// - Returns: Google FormのURL
    private static func getGeneralKnowledgeURL(for day: Int) -> String {
        // ここに実際のGoogle FormのURLを日ごとに設定してください

        switch day {
        case 1: return "https://docs.google.com/forms/d/e/1FAIpQLScNDnq_WVfOeYnr8FfIRBVqxYpz7baEqa18HsI8rVCqU322Qw/viewform?usp=header"
        case 2: return "https://docs.google.com/forms/d/e/1FAIpQLSc2URWEBq6Wk9lBljB_DI9vsHHH6fLG1DIMv8ZastfqQN8_2A/viewform?usp=header"
        case 3: return "https://docs.google.com/forms/d/e/1FAIpQLSdqLxzyyv1dKZ9dGC_A8lTIW9k0d_TnE_NCUUKobAk0VqKhGA/viewform?usp=header"
        case 4: return "https://docs.google.com/forms/d/e/1FAIpQLSdWFt_SXmFsjZ4IJmNhWe9B612NTgG0l31IyDo-1rCvOwsSmw/viewform?usp=header"
        case 5: return "https://docs.google.com/forms/d/e/1FAIpQLSdkH0ctaW1NQVO3ISyWoXQ4pgpP25VAkgfectnKs31pvkASDQ/viewform?usp=header"
        case 6: return "https://docs.google.com/forms/d/e/1FAIpQLSeIqTFdfe8zchVHkheKJfCMeEflEVs8knLH_ofl8p7OP1zLug/viewform?usp=header"
        case 7: return "https://docs.google.com/forms/d/e/1FAIpQLSeph8V4V-TEt6VGwP9525RZYN1Jh0VOzdeeu7s9qajlRvLeBw/viewform?usp=header"
        case 8: return "https://docs.google.com/forms/d/e/1FAIpQLSdDs-zDorpD3cV8k_H5Ggt6Lial8vbYnuHnK8dsb9eYx7S5Rw/viewform?usp=header"
        case 9: return "https://docs.google.com/forms/d/e/1FAIpQLSfJWMV4q_zDIap2lN6_z6bsYIttKt_5OZVxdbI0eK-JDsNPXQ/viewform?usp=header"
        case 10: return "https://docs.google.com/forms/d/e/1FAIpQLSevzZ00qX7oBBe1dZV4r2TQz3sxm0uiZfxjXtRSdrZqKLqHtw/viewform?usp=header"
        case 11: return "https://docs.google.com/forms/d/e/1FAIpQLSfRIQEWbWAksa-YHmNHDOWKBHX04X29w5Cjd1ur9Q2Kc3qRSw/viewform?usp=publish-editor"
        case 12: return "https://docs.google.com/forms/d/e/1FAIpQLSe8HN4V3E0CtbS9VjFUe1rTitiKAwEE9fNagiddDUfY1iQBYA/viewform?usp=header"
        case 13: return "https://docs.google.com/forms/d/e/1FAIpQLSdZwXjGJ6h8yCi48LHupUCM4ftliUl-ZgYH5GfgqRSWCdbJLg/viewform?usp=publish-editor"
        case 14: return "https://docs.google.com/forms/d/e/1FAIpQLSejcNi3KRCcYXAafTkCu2fKRZdclLJ6PLQxzdqVOFTXzu39mQ/viewform?usp=publish-editor"
        
        default: return ""
        }
    }
    
    /// 動画視聴課題のURLを取得
    /// - Parameter day: 日数（4または11）
    /// - Returns: Google FormのURL
    private static func getVideoWatchingURL(for day: Int) -> String {
        // ここに実際のGoogle FormのURLを日ごとに設定してください
        // day 4と11で異なるURLを返すことができます
        
        switch day {
        case 4:
            return "https://docs.google.com/forms/d/e/1FAIpQLSeqw3Wd51hiymkF65gEV4fevXfLOU7vxJsq9ru_YJZetuoO_w/viewform?usp=header"
        case 11:
            return "https://docs.google.com/forms/d/e/1FAIpQLSeX2Hod29ugIJA-UpARzNT_BzbjHdl-pJWd4s1iDZFBClQX-g/viewform?usp=header"
        default:
            return ""
        }
    }
}

// 後方互換性のために既存のTaskManagerを残す（段階的移行用）
typealias TaskManager = EventKitTaskManager 