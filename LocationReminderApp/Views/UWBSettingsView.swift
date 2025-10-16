import SwiftUI
import CoreBluetooth
import NearbyInteraction
import UserNotifications
import BackgroundTasks
import CoreLocation
import os
import Foundation

// 座標データ保存用の構造体
struct CoordinateData: Codable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// NotificationManager クラス
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    // ScreenTimeManagerへの参照を追加
    weak var screenTimeManager: ScreenTimeManager?
    
    private override init() {
        super.init()
        setupNotificationCenter()
        checkNotificationPermission()
        
        // 自動リクエストはしない（オンボーディングで処理）
    }
    
    private func setupNotificationCenter() {
        // UNUserNotificationCenterのdelegateを設定
        UNUserNotificationCenter.current().delegate = self
        print("📱 NotificationManager: 通知センターのデリゲートを設定")
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
            
            if let error = error {
                print("通知許可エラー: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // Screen Time制限が有効になる条件をチェック（ScreenTimeManagerと同じロジック）
    private func shouldEnableRestrictionBasedOnTasks(todayTasks: [TaskItem]) -> Bool {
        let now = Date()
        
        print("\n=== 🕒 通知用タスク時刻条件チェック ===")
        print("📅 当日のタスク総数: \(todayTasks.count)")
        
        // 当日のタスクがない場合は通知不要
        guard !todayTasks.isEmpty else { 
            print("❌ 当日のタスクなし - 通知不要")
            print("===============================\n")
            return false 
        }
        
        // 未完了のタスクのみをチェック対象とする
        let incompleteTasks = todayTasks.filter { !$0.isCompleted }
        print("📊 未完了タスク数: \(incompleteTasks.count)")
        
        guard !incompleteTasks.isEmpty else {
            print("✅ 未完了タスクなし - 通知不要")
            print("===============================\n")
            return false
        }
        
        // 時刻が設定されているタスクをチェック
        let tasksWithTime = incompleteTasks.filter { $0.hasTime }
        print("⏰ 時刻設定タスク数: \(tasksWithTime.count)")
        
        if !tasksWithTime.isEmpty {
            // 時刻設定されたタスクがある場合、タスク時刻が現在時刻以前（つまり時刻が来た）のタスクがあるかチェック
            let activeTasksToday = tasksWithTime.filter { task in
                task.dueDate <= now
            }
            print("🔥 時刻が到来したタスク数: \(activeTasksToday.count)")
            
            if !activeTasksToday.isEmpty {
                print("✅ 通知すべきタスクあり（時刻到来済み）")
                for task in activeTasksToday {
                    let timeStr = DateFormatter.localizedString(from: task.dueDate, dateStyle: .none, timeStyle: .short)
                    print("  - \(task.title) (\(timeStr)) - 時刻到来済み")
                }
            } else {
                print("❌ まだ時刻が来ていないタスクのみ - 通知不要")
                for task in tasksWithTime {
                    let timeStr = DateFormatter.localizedString(from: task.dueDate, dateStyle: .none, timeStyle: .short)
                    print("  - \(task.title) (\(timeStr)) - まだ時刻前")
                }
            }
            print("===============================\n")
            return !activeTasksToday.isEmpty
        } else {
            // 時刻設定されていないタスクのみの場合、未完了タスクがあれば通知
            print("✅ 時刻未設定の未完了タスクあり - 通知必要")
            print("===============================\n")
            return true
        }
    }

    func setRoomStatusNotification(deviceName: String, isInBubble: Bool, todayTasks: [TaskItem] = []) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Territory"
        
        if isInBubble {
            // Screen Time制限が有効になる条件をチェック
            let shouldShowTaskNotification = shouldEnableRestrictionBasedOnTasks(todayTasks: todayTasks)
            
            // Screen Time制限条件を満たす場合のみ通知を表示
            guard shouldShowTaskNotification else { return }
            
            content.subtitle = "🔥タスク開始の時間です🔥"
            
            if todayTasks.count == 1 {
                // 単一タスクの場合、タスク名を含める
                content.body = "\"\(todayTasks.first!.title)\"を始めましょう！"
            } else {
                // 複数タスクの場合
                content.body = "やるべきタスクがあります！始めましょう！"
            }
        } else {
            // Secure Bubble外では「休憩しましょう」通知は、Screen Time制限が有効になる条件を満たしている場合のみ表示
            let shouldShowRestNotification = shouldEnableRestrictionBasedOnTasks(todayTasks: todayTasks)
            
            // Screen Time制限条件を満たす場合のみ通知を表示
            guard shouldShowRestNotification else { return }
            
            content.subtitle = "🎐少し休憩しましょう🎐"
            content.body = "深呼吸しましょう。"
        }
        
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "RoomStatus_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知送信エラー: \(error.localizedDescription)")
            }
        }
    }
}

// QorvoNIサービスの定義
struct QorvoNIService {
    static let serviceUUID = CBUUID(string: "2E938FD0-6A61-11ED-A1EB-0242AC120002")
    static let scCharacteristicUUID = CBUUID(string: "2E93941C-6A61-11ED-A1EB-0242AC120002")
    static let rxCharacteristicUUID = CBUUID(string: "2E93998A-6A61-11ED-A1EB-0242AC120002")
    static let txCharacteristicUUID = CBUUID(string: "2E939AF2-6A61-11ED-A1EB-0242AC120002")
}

// メッセージプロトコル
enum MessageId: UInt8 {
    case accessoryConfigurationData = 0x1
    case accessoryUwbDidStart = 0x2
    case accessoryUwbDidStop = 0x3
    case accessoryPaired = 0x4
    case initialize = 0xA
    case configureAndStart = 0xB
    case stop = 0xC
    
    // User defined/notification messages
    case getReserved = 0x20
    case setReserved = 0x21
    case iOSNotify = 0x2F
}

// デバイス状態
enum DeviceStatus: String, CaseIterable {
    case discovered = "発見済み"
    case connected = "接続済み"
    case paired = "ペアリング済み"
    case ranging = "距離測定中"
}

// 保存用デバイス情報
struct SavedDeviceInfo: Codable {
    let peripheralIdentifier: String
    let uniqueID: Int
    let name: String
    let savedDate: Date
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    // アプリがフォアグラウンドにある時の通知表示制御
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        print("\n=== 📱 フォアグラウンド通知受信 ===")
        print("🔔 通知ID: \(notification.request.identifier)")
        print("📝 タイトル: \(notification.request.content.title)")
        print("📄 内容: \(notification.request.content.body)")
        
        // リマインダー通知かどうかをチェック
        if isReminderNotification(notification) {
            print("✅ リマインダー通知を検出")
            handleReminderNotificationReceived(notification)
        }
        
        // フォアグラウンドでは通知を表示しない
        completionHandler([])
        print("=====================================\n")
    }
    
    // 通知タップ時の処理
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        print("\n=== 📱 通知タップ受信 ===")
        print("🔔 通知ID: \(response.notification.request.identifier)")
        print("📝 アクション: \(response.actionIdentifier)")
        
        let notification = response.notification
        
        // リマインダー通知かどうかをチェック
        if isReminderNotification(notification) {
            print("✅ リマインダー通知のタップを検出")
            handleReminderNotificationReceived(notification)
        }
        
        completionHandler()
        print("===========================\n")
    }
    
    // リマインダー通知かどうかを判定
    private func isReminderNotification(_ notification: UNNotification) -> Bool {
        let identifier = notification.request.identifier
        let title = notification.request.content.title
        let _ = notification.request.content.body
        
        // リマインダー通知の特徴をチェック
        // 1. Bundle IDがリマインダーアプリのもの
        // 2. タイトルや内容にリマインダー関連のキーワードが含まれる
        let isReminderApp = identifier.contains("com.apple.remindd") ||
                           identifier.contains("reminder") ||
                           title.contains("リマインダー") ||
                           title.contains("Reminder")
        
        print("🔍 リマインダー通知判定: \(isReminderApp)")
        print("   - ID: \(identifier)")
        print("   - タイトル: \(title)")
        
        return isReminderApp
    }
    
    // リマインダー通知受信時の処理
    private func handleReminderNotificationReceived(_ notification: UNNotification) {
        print("\n=== 🔔 リマインダー通知処理開始 ===")
        
        // Screen Time制限のチェックを実行
        guard let screenTimeManager = screenTimeManager else {
            print("❌ ScreenTimeManagerが利用できません")
            print("=====================================\n")
            return
        }
        
        // Screen Timeが認証されていない場合はスキップ
        guard screenTimeManager.isAuthorized else {
            print("⚠️ Screen Time未認証のため処理をスキップ")
            print("=====================================\n")
            return
        }
        
        print("📋 リマインダー通知検知 - Screen Time制限状態をチェック")
        
        // 少し遅延を入れてからチェック（通知処理の完了を待つ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // リマインダー通知専用の処理を実行
            screenTimeManager.handleReminderNotificationReceived()
        }
        
        print("✅ リマインダー通知処理完了")
        print("=====================================\n")
    }
}

// UWBデバイスモデル
class UWBDevice: ObservableObject, Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let uniqueID: Int
    @Published var name: String
    @Published var status: DeviceStatus = .discovered
    @Published var distance: Float?
    @Published var lastUpdate: Date
    
    var scCharacteristic: CBCharacteristic?
    var rxCharacteristic: CBCharacteristic?
    var txCharacteristic: CBCharacteristic?
    
    init(peripheral: CBPeripheral, uniqueID: Int, name: String) {
        self.peripheral = peripheral
        self.uniqueID = uniqueID
        self.name = name
        self.lastUpdate = Date()
    }
}

// UWB管理クラス
class UWBManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = UWBManager()
    
    @Published var discoveredDevices: [UWBDevice] = []
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var scanningError: String?
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var niPermissionError: String?
    @Published var niPermissionStatus: String = "未確認"
    @Published var isUWBActive = false // UWB通信がアクティブかどうか
    @Published var currentDistance: Float? = nil // 現在の距離測定値
    @Published var hasConnectedDevices = false // 接続済みデバイスがあるかどうか
    @Published var isInSecureBubble = false // secure bubble内にいるかどうか
    @Published var notificationsEnabled = true // 通知が有効かどうか
    @Published var isBackgroundMode = false // バックグラウンドモードかどうか
    @Published var backgroundSessionActive = false // バックグラウンドセッションがアクティブかどうか
    @Published var isRepairing = false // 再ペアリング処理中かどうか
    @Published var repairAttemptCount: Int = 0 // 再ペアリング試行回数
    
    // ジオフェンシング関連
    @Published var homeLocationSet = false // 自宅位置が設定されているか
    @Published var isAtHome = false // 現在自宅にいるか
    @Published var geofencingEnabled = false // ジオフェンシングが有効か
    @Published var geofencingMonitoring = false // ジオフェンシング監視が実際に動作しているか（UWB接続時は一時停止）
    @Published var locationPermissionStatus = "未設定" // 位置情報許可状態
    @Published var geofenceDebugNotificationEnabled = true // ジオフェンスデバッグ通知が有効か
    @Published var uwbPairingDebugNotificationEnabled = true // UWBペアリングデバッグ通知が有効か
    
    // TaskManagerへの参照を追加
    weak var taskManager: EventKitTaskManager?
    
    // ScreenTimeManagerへの参照を追加
    weak var screenTimeManager: ScreenTimeManager?
    
    // 統計データ収集用
    private let userDefaults = UserDefaults.standard
    private let bubbleSessionsKey = "uwb_bubble_sessions"
    private var currentOutsideStartTime: Date?
    private var todayBreakCount: Int = 0
    
    // 統計データ構造
    struct BubbleSession: Codable {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let isOutside: Bool // true: bubble外, false: bubble内
        let taskId: String? // 関連するタスクのID
    }
    
    private var centralManager: CBCentralManager?
    private var niSessions: [Int: NISession] = [:]
    private var accessoryConfigurations: [Int: NINearbyAccessoryConfiguration] = [:]
    private var permissionTestSession: NISession?
    private let logger = os.Logger(subsystem: "com.pomodororeminder.uwb", category: "UWBManager")
    private let savedDevicesKey = "saved_uwb_devices"
    private let notificationManager = NotificationManager.shared
    
    // ⚠️Secure bubble のしきい値変更できない？
    private let secureBubbleInnerThreshold: Float = 0.2 // -.-m以内でbubbleの中
    private let secureBubbleOuterThreshold: Float = 1.2 // -.-m以上でbubbleの外
    private var previousSecureBubbleStatus: Bool? = nil // 前回のsecure bubble状態
    
    // バックグラウンド処理関連
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundMaintenanceTimer: Timer?
    private var isProcessingBackgroundTask = false
    private let backgroundTaskIdentifier_uwb = "com.locationreminder.app.uwb.maintenance"
    
    // 指数バックオフ用のプロパティ
    private var currentBGTaskInterval: TimeInterval = 60 // 初期値: 60秒（1分）
    private let minBGTaskInterval: TimeInterval = 60 // 最小: 60秒（1分）
    private let maxBGTaskInterval: TimeInterval = 3600 // 最大: 3600秒（60分）
    private var heartbeatTimer: Timer?
    private var lastBackgroundUpdate = Date()
    private var backgroundHeartbeatStartTime: Date?
    
    // フォアグラウンド自動修復関連
    private var foregroundMonitorTimer: Timer?
    private var lastDistanceUpdateTime: Date?
    private let foregroundCheckInterval: TimeInterval = 15.0  // 15秒間隔でチェック
    
    // ジオフェンシング関連
    private let locationManager_geo = CLLocationManager()
    private var homeCoordinate: CLLocationCoordinate2D?
    private var homeRadius: CLLocationDistance = 100.0 // 100m範囲（デフォルト値）
    private let homeLocationKey = "home_location_coordinate"
    private var backgroundActivitySession: Any? // CLBackgroundActivitySession（iOS 17+）
    
    // CurrentLocationGetterの参照を保持（ガベージコレクションを防ぐため）
    var currentLocationGetter: CurrentLocationGetter?
    
    private var locationMonitor: Any? // iOS 18のCLMonitor（利用可能な場合）
    private let maxDistanceUpdateDelay: TimeInterval = 60.0   // 60秒間距離更新がない場合に修復
    
    // 再ペアリング関連
    private var repairTimers: [Int: Timer] = [:]  // デバイス毎の再ペアリングタイマー
    private var repairAttempts: [Int: Int] = [:]  // デバイス毎の再試行回数
    private let maxRepairAttempts = 10  // 最大再試行回数
    private let baseRepairInterval: TimeInterval = 2.0  // 基本再試行間隔（秒）
    private let maxRepairInterval: TimeInterval = 60.0  // 最大再試行間隔（秒・フォアグラウンド）
    // バックグラウンド: 最大20秒間隔、各試行は個別のbackgroundTaskで保護
    
    // バックグラウンド再ペアリング管理用（1台限定）
    private var repairingDeviceID: Int? = nil  // 再ペアリングが必要なデバイスID（1台のみ）
    private var lastRepairTime: Date = Date.distantPast  // 最後の再ペアリング試行時刻
    
    private override init() {
        super.init()
        // CBCentralManagerの初期化は完全に遅延させる
        // 初期化時にインスタンスを作成しないことで、Bluetoothダイアログを完全に回避
        self.centralManager = nil
        
        // 通知許可の自動リクエストはしない（オンボーディングで処理）
        // self.notificationManager.requestAuthorization()
        
        self.setupBackgroundProcessing()
        self.setupLocationServices()
        self.loadHomeLocation()
    }
    
    // Bluetooth delegateを有効化する（オンボーディング完了後に呼ばれる）
    func enableBluetoothDelegate() {
        // 既にCBCentralManagerが作成済みの場合はスキップ
        guard self.centralManager == nil else {
            print("📡 UWBManager: CBCentralManagerは既に初期化済みです")
            return
        }
        
        // CBCentralManagerを作成（この時点で初めてBluetoothの状態チェックが走る）
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        print("📡 UWBManager: CBCentralManagerを初期化しました")
    }
    
    // 当日までのタスク（期限切れも含む）を取得するメソッド
    private func getTasksDueUntilToday() -> [TaskItem] {
        guard let taskManager = taskManager else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return taskManager.tasks.filter { task in
            let taskDueDate = Calendar.current.startOfDay(for: task.dueDate)
            return taskDueDate <= today
        }
    }
    
    func startScanning() {
        guard let centralManager = centralManager else { return }
        
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(
                withServices: [QorvoNIService.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            self.isScanning = true
            self.scanningError = nil
        } else {
            self.scanningError = "Bluetoothが利用できません"
        }
    }
    
    func stopScanning() {
        self.centralManager?.stopScan()
        self.isScanning = false
    }
    
    func connectToDevice(_ device: UWBDevice) {
        guard let centralManager = self.centralManager else { return }
        
        logger.info("📱 接続開始: \(device.name)")
        
        // デバッグ通知: Bluetooth接続開始
        sendUWBPairingDebugNotification(
            title: "📱 UWB接続開始",
            message: "Bluetooth接続を開始します",
            deviceName: device.name
        )
        
        self.isConnecting = true
        device.status = .connected
        
        // 認証エラーを避けるため、適切な接続オプションを設定
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ]
        
        centralManager.connect(device.peripheral, options: options)
    }
    
    func disconnectFromDevice(_ device: UWBDevice) {
        guard let centralManager = self.centralManager else { return }
        
        logger.info("📱 切断: \(device.name)")
        centralManager.cancelPeripheralConnection(device.peripheral)
        
        // NISessionを無効化
        if let session = self.niSessions[device.uniqueID] {
            session.invalidate()
            self.niSessions.removeValue(forKey: device.uniqueID)
        }
        self.accessoryConfigurations.removeValue(forKey: device.uniqueID)
        
        // 再ペアリングプロセスも停止
        self.stopRepairProcess(for: device)
        
        DispatchQueue.main.async {
            device.status = DeviceStatus.discovered
            device.distance = nil
            
            // Secure Bubble状態をリセット（手動切断時）
            self.isInSecureBubble = false
            self.previousSecureBubbleStatus = false
        }
        
        // 手動切断時にScreenTime制限を自動解除
        if let screenTimeManager = screenTimeManager {
            logger.info("🔓 手動切断によりScreenTime制限を自動解除")
            screenTimeManager.disableRestrictionForSecureBubble()
        }
        
        // UWB切断時にジオフェンス監視を再開
        resumeGeofenceMonitoring()
        
        // BGタスク間隔をリセット（次回の再接続を素早く試みるため）
        resetBackgroundTaskInterval()
        
        self.updateConnectionStatus()
    }
    
    func disconnectAllDevices() {
        guard let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) else {
            return
        }
        
        disconnectFromDevice(connectedDevice)
        
        // 全ての再ペアリングプロセスを停止
        stopAllRepairProcesses()
        
        logger.info("�� 全デバイス切断完了")
    }
    
    func removeDeviceFromSaved(_ device: UWBDevice) {
        var savedDevices = loadSavedDevices()
        savedDevices.removeAll { $0.peripheralIdentifier == device.peripheral.identifier.uuidString }
        
        if let encoded = try? JSONEncoder().encode(savedDevices) {
            UserDefaults.standard.set(encoded, forKey: savedDevicesKey)
            logger.info("保存デバイス削除: \(device.name)")
        }
    }
    
    func isDeviceSaved(_ device: UWBDevice) -> Bool {
        let savedDevices = loadSavedDevices()
        return savedDevices.contains { $0.peripheralIdentifier == device.peripheral.identifier.uuidString }
    }
    
    func requestNearbyInteractionPermission() {
        logger.info("🔵 Nearby Interaction許可を要求開始")
        
        // デバイスがUWBをサポートしているかチェック
        if #available(iOS 16.0, *) {
            guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
                DispatchQueue.main.async {
                    self.niPermissionError = "このデバイスはUWB（Nearby Interaction）をサポートしていません"
                    self.niPermissionStatus = "非対応"
                }
                logger.error("❌ デバイスがUWBをサポートしていません")
                return
            }
        }
        
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可要求中..."
            self.niPermissionError = nil
        }
        
        // 実際に許可ダイアログを表示する正しい方法
        requestNearbyInteractionPermissionCorrectly()
    }
    
    // 正しい方法でNearby Interactionの許可ダイアログを表示
    private func requestNearbyInteractionPermissionCorrectly() {
        logger.info("🔵 正しい方法でNI許可ダイアログを表示")
        
        // 許可テスト用セッションを作成
        permissionTestSession = NISession()
        permissionTestSession?.delegate = self
        
        // iOS 16以降では、従来の方法を使用（NIDiscoveryTokenは直接初期化できない）
        if #available(iOS 16.0, *) {
            // iOS 16以降でも従来の方法を使用
            tryLegacyPermissionRequest()
        } else {
            // iOS 15以前の場合、従来の方法を使用
            tryLegacyPermissionRequest()
        }
        
        // 15秒後にタイムアウト処理（許可ダイアログが表示されない場合）
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            if self.niPermissionStatus == "許可要求中..." {
                self.logger.error("❌ 許可ダイアログ表示タイムアウト")
                DispatchQueue.main.async {
                    self.niPermissionStatus = "エラー"
                    self.niPermissionError = "許可ダイアログが表示されませんでした。Info.plistとentitlementsの設定を確認してください。"
                }
                self.permissionTestSession?.invalidate()
                self.permissionTestSession = nil
            }
        }
    }
    
    // 従来の方法でNearby Interactionの許可を要求
    private func tryLegacyPermissionRequest() {
        logger.info("🔵 簡易的なNI許可要求")
        
        // 許可ダイアログを表示するために、NISessionを作成して空の状態で実行を試みる
        // これにより、システムが許可ダイアログを表示する
        
        // 単純にNISessionを作成して、許可状態をチェック
        DispatchQueue.main.async {
            self.niPermissionStatus = "確認中..."
        }
        
        // 5秒後にタイムアウト処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.niPermissionStatus == "確認中..." {
                // 実際のデバイス接続時に許可ダイアログが表示されるため、
                // ここでは許可状態を「未確認」として処理
                self.niPermissionStatus = "デバイス接続時に確認"
                self.niPermissionError = "UWBデバイスに接続する際に、Nearby Interactionの許可ダイアログが表示されます。"
            }
            
            // 許可テスト用セッションをクリーンアップ
            self.permissionTestSession?.invalidate()
            self.permissionTestSession = nil
        }
        
        logger.info("✅ 許可確認処理完了 - 実際の許可はデバイス接続時")
    }
    
    // 代替の許可要求方法
    private func tryAlternativePermissionRequest() {
        logger.info("🔵 代替方法でNI許可要求")
        
        // 実際の許可はデバイス接続時に行われるため、ここでは状態を設定のみ
        DispatchQueue.main.async {
            self.niPermissionStatus = "デバイス接続時に確認"
            self.niPermissionError = "UWBデバイスとの接続時に、Nearby Interactionの許可が要求されます。"
        }
        
        // 許可テスト用セッションをクリーンアップ
        self.permissionTestSession?.invalidate()
        self.permissionTestSession = nil
    }
    
    private func sendDataToDevice(_ data: Data, device: UWBDevice) {
        guard let rxCharacteristic = device.rxCharacteristic else {
            logger.error("RX Characteristicが見つかりません")
            return
        }
        
        let mtu = device.peripheral.maximumWriteValueLength(for: .withResponse)
        let bytesToSend = min(mtu, data.count)
        let dataToSend = data.prefix(bytesToSend)
        
        logger.info("データ送信: \(dataToSend.count) bytes to \(device.name)")
        device.peripheral.writeValue(Data(dataToSend), for: rxCharacteristic, type: .withResponse)
    }
    
    private func handleReceivedData(_ data: Data, from device: UWBDevice) {
        guard let messageId = MessageId(rawValue: data.first ?? 0) else {
            logger.error("無効なメッセージID")
            return
        }
        
        switch messageId {
        case .accessoryConfigurationData:
            handleAccessoryConfigurationData(data.dropFirst(), device: device)
        case .accessoryUwbDidStart:
            handleUWBDidStart(device: device)
        case .accessoryUwbDidStop:
            handleUWBDidStop(device: device)
        case .accessoryPaired:
            handleAccessoryPaired(device: device)
        case .iOSNotify:
            handleiOSNotify(data: data, device: device)
        case .getReserved:
            logger.debug("Get not implemented in this version")
        case .setReserved:
            logger.debug("Set not implemented in this version")
        default:
            logger.info("未対応のメッセージ: \(String(describing: messageId))")
        }
    }
    
    private func handleAccessoryConfigurationData(_ configData: Data, device: UWBDevice) {
        do {
            // iOS 15対応: データから直接設定を作成
            let configuration = try NINearbyAccessoryConfiguration(
                accessoryData: configData,
                bluetoothPeerIdentifier: device.peripheral.identifier
            )
            
            accessoryConfigurations[device.uniqueID] = configuration
            logger.info("📡 設定データ受信・保存: \(device.name)")
            
            // 既存のNISessionがある場合は無効化
            if let existingSession = niSessions[device.uniqueID] {
                existingSession.invalidate()
                logger.info("既存NISessionを無効化: \(device.name)")
            }
            
            // NISessionを開始（ここで許可ダイアログが表示される）
            let session = NISession()
            session.delegate = self
            niSessions[device.uniqueID] = session
            
            // 実際のrun()でNI許可ダイアログが表示される
            session.run(configuration)
            
            // UI状態を更新
            DispatchQueue.main.async {
                self.niPermissionStatus = "許可要求中..."
            }
            
            logger.info("📱 新しいNISession開始: \(device.name)")
            
        } catch {
            logger.error("設定データ解析失敗: \(error)")
            handleNIError(error)
        }
    }
    
    private func handleUWBDidStart(device: UWBDevice) {
        logger.info("🎯 UWB距離測定開始通知受信: \(device.name)")
        logger.info("   - 前回のステータス: \(device.status.rawValue)")
        
        DispatchQueue.main.async {
            device.status = DeviceStatus.ranging
        }
        updateConnectionStatus()
        
        logger.info("✅ デバイスステータスをrangingに更新")
        logger.info("   👉 次のステップ: session(_:didUpdate:)で距離データ受信待ち")
    }
    
    private func handleUWBDidStop(device: UWBDevice) {
        DispatchQueue.main.async {
            device.status = DeviceStatus.connected
            device.distance = nil
        }
        updateConnectionStatus()
        logger.info("📡 UWB測定停止: \(device.name)")
    }
    
    private func handleAccessoryPaired(device: UWBDevice) {
        DispatchQueue.main.async {
            device.status = DeviceStatus.paired
        }
        updateConnectionStatus()
        
        // デバッグ通知: ペアリング成功
        sendUWBPairingDebugNotification(
            title: "✅ UWBペアリング成功",
            message: "デバイスとのペアリングが完了しました",
            deviceName: device.name
        )
        
        // デバイス情報を保存
        saveDeviceInfo(device)
        
        // 初期化メッセージを送信
        let initMessage = Data([MessageId.initialize.rawValue])
        sendDataToDevice(initMessage, device: device)
        
        logger.info("アクセサリペアリング完了: \(device.name)")
    }
    
    private func handleiOSNotify(data: Data, device: UWBDevice) {
        // メッセージの解析
        if data.count > 3, let message = String(bytes: data.advanced(by: 3), encoding: .utf8) {
            
            // デバイスからのメッセージを直接解釈して、bubbleの状態を判断する
            // これにより、アプリ内の状態更新とのタイムラグの問題を解消する
            let isInBubbleBasedOnMessage = message.contains("in")
            
            // 初回判定または前回の状態から変更がある場合に処理
            let shouldProcess = previousSecureBubbleStatus == nil || previousSecureBubbleStatus != isInBubbleBasedOnMessage
            
            if shouldProcess {
                DispatchQueue.main.async {
                    self.isInSecureBubble = isInBubbleBasedOnMessage
                }
                
                // セッション記録
                self.recordBubbleStateChange(isInBubble: isInBubbleBasedOnMessage)
                
                previousSecureBubbleStatus = isInBubbleBasedOnMessage
                
                // 通知設定が有効な場合のみ通知を送信
                if notificationsEnabled {
                    let todayTasks = getTasksDueUntilToday()
                    notificationManager.setRoomStatusNotification(
                        deviceName: device.name,
                        isInBubble: isInBubbleBasedOnMessage,
                        todayTasks: todayTasks
                    )
                }
                
                // フォアグラウンドまたはバックグラウンドでの適切な処理
                if isBackgroundMode {
                    handleBackgroundSecureBubbleChange(isInBubble: isInBubbleBasedOnMessage)
                }
            }
        }
    }
    
    private func handleBackgroundSecureBubbleChange(isInBubble: Bool) {
        // バックグラウンドでの軽量な処理のみ実行
        lastBackgroundUpdate = Date()
        
        // 必要に応じてタスクマネージャーに状態変化を通知
        if taskManager != nil {
            DispatchQueue.main.async {
                // TaskManagerの状態更新処理（軽量化）
                // 詳細なUI更新はフォアグラウンド復帰時に実行
            }
        }
    }
    
    private func checkSecureBubbleStatus(distance: Float, device: UWBDevice) {
        let isCurrentlyInBubble: Bool
        
        if distance <= secureBubbleInnerThreshold {
            isCurrentlyInBubble = true
        } else if distance >= secureBubbleOuterThreshold {
            isCurrentlyInBubble = false
        } else {
            // 0.2m〜1.2mの間は前回の状態を保持（ヒステリシス）
            isCurrentlyInBubble = isInSecureBubble
        }
        
        // 初回判定または状態が変化した場合に通知
        let shouldNotify = previousSecureBubbleStatus == nil || previousSecureBubbleStatus != isCurrentlyInBubble
        
        if shouldNotify {
            // フォアグラウンド時のシンプルログ
            if !isBackgroundMode {
                let screenTimeStatus = screenTimeManager?.isRestrictionEnabled == true ? "有効" : "無効"
                logger.info("📍 距離: \(String(format: "%.2f", distance))m | Bubble: \(isCurrentlyInBubble ? "内部" : "外部") | ScreenTime: \(screenTimeStatus)")
            }
            
            DispatchQueue.main.async {
                self.isInSecureBubble = isCurrentlyInBubble
            }
            
            // セッション記録
            self.recordBubbleStateChange(isInBubble: isCurrentlyInBubble)
            
            previousSecureBubbleStatus = isCurrentlyInBubble
            
            // 通知設定が有効な場合のみ通知を送信
            if notificationsEnabled {
                let todayTasks = getTasksDueUntilToday()
                notificationManager.setRoomStatusNotification(
                    deviceName: device.name,
                    isInBubble: isCurrentlyInBubble,
                    todayTasks: todayTasks
                )
            }
        }
    }
    
    private func findDevice(peripheral: CBPeripheral) -> UWBDevice? {
        return discoveredDevices.first { $0.peripheral == peripheral }
    }
    
    private func findDevice(uniqueID: Int) -> UWBDevice? {
        return discoveredDevices.first { $0.uniqueID == uniqueID }
    }
    
    // 接続状態を更新
    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            let connectedDevices = self.discoveredDevices.filter {
                $0.status == .connected || $0.status == .paired || $0.status == .ranging
            }
            self.hasConnectedDevices = !connectedDevices.isEmpty
            
            // 距離測定中のデバイスがあるかチェック
            let rangingDevices = self.discoveredDevices.filter { $0.status == .ranging }
            self.isUWBActive = !rangingDevices.isEmpty
            
            // 現在の距離を更新（複数デバイスがある場合は最初のものを使用）
            self.currentDistance = rangingDevices.first?.distance
        }
    }
    
    // デバイス情報を保存
    private func saveDeviceInfo(_ device: UWBDevice) {
        let deviceInfo = SavedDeviceInfo(
            peripheralIdentifier: device.peripheral.identifier.uuidString,
            uniqueID: device.uniqueID,
            name: device.name,
            savedDate: Date()
        )
        
        var savedDevices = loadSavedDevices()
        // 既存のデバイスを削除してから追加（重複防止）
        savedDevices.removeAll { $0.peripheralIdentifier == deviceInfo.peripheralIdentifier }
        savedDevices.append(deviceInfo)
        
        // 最新の5台まで保存
        if savedDevices.count > 5 {
            savedDevices = Array(savedDevices.suffix(5))
        }
        
        if let encoded = try? JSONEncoder().encode(savedDevices) {
            UserDefaults.standard.set(encoded, forKey: savedDevicesKey)
            logger.info("デバイス情報保存: \(device.name)")
        }
    }
    
    // 保存されたデバイス情報を読み込み
    private func loadSavedDevices() -> [SavedDeviceInfo] {
        guard let data = UserDefaults.standard.data(forKey: savedDevicesKey),
              let devices = try? JSONDecoder().decode([SavedDeviceInfo].self, from: data) else {
            return []
        }
        return devices
    }
    
    // 自動接続を開始
    private func startAutoReconnection() {
        guard let centralManager = centralManager,
              centralManager.state == .poweredOn else { return }
        
        let savedDevices = loadSavedDevices()
        guard !savedDevices.isEmpty else { return }
        
        logger.info("自動接続開始: \(savedDevices.count)台のデバイス")
        
        // 保存されたデバイスのUUIDを取得
        let peripheralUUIDs = savedDevices.compactMap { UUID(uuidString: $0.peripheralIdentifier) }
        
        // 既知のペリフェラルを取得
        let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: peripheralUUIDs)
        
        for peripheral in knownPeripherals {
            if let savedDevice = savedDevices.first(where: { $0.peripheralIdentifier == peripheral.identifier.uuidString }) {
                // 新しいUWBDeviceオブジェクトを作成
                let device = UWBDevice(
                    peripheral: peripheral,
                    uniqueID: savedDevice.uniqueID,
                    name: savedDevice.name
                )
                
                // デバイスリストに追加
                DispatchQueue.main.async {
                    if !self.discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                        self.discoveredDevices.append(device)
                    }
                }
                
                // 🔧 改善: 既に接続されているデバイスの場合も再ペアリングをチェック
                if peripheral.state == .connected {
                    logger.info("✅ 既にBluetooth接続済み: \(savedDevice.name) - NISession状態をチェック")
                    
                    // 少し待ってから再ペアリング状態をチェック（自宅内の場合のみ）
                    if isAtHome {
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                            // デバイスリストから再取得
                            if let existingDevice = self.discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
                                let deviceID = existingDevice.uniqueID
                                let hasNISession = self.niSessions[deviceID] != nil
                                
                                if !hasNISession {
                                    self.logger.info("⚡ 自動再接続: NISession不在のため再ペアリング実行")
                                    self.attemptNISessionRepair(for: existingDevice)
                                } else {
                                    self.logger.info("✅ 自動再接続: NISession確認完了")
                                }
                            }
                        }
                    }
                } else {
                    // 未接続の場合は自動接続開始
                    logger.info("🔌 自動接続試行: \(savedDevice.name)")
                    let options: [String: Any] = [
                        CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                        CBConnectPeripheralOptionNotifyOnNotificationKey: true
                    ]
                    centralManager.connect(peripheral, options: options)
                }
            }
        }
        
        // 見つからなかったデバイスのためにスキャンも開始
        if knownPeripherals.count < savedDevices.count {
            startScanning()
        }
    }
    
    // タイムアウトしたデバイスをクリーンアップ
    private func cleanupTimeoutDevices() {
        let timeoutInterval: TimeInterval = 5.0
        let now = Date()
        
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { device in
                device.status == DeviceStatus.discovered && now.timeIntervalSince(device.lastUpdate) > timeoutInterval
            }
        }
    }
    
    
    // NISessionエラーのユーザーフレンドリーな説明
    private func handleNIError(_ error: Error) {
        let niError = error as NSError
        
        // 許可テスト用セッションのエラーかチェック
        let isPermissionTest = (permissionTestSession != nil)
        
        logger.info("🔴 NISessionエラー: コード=\(niError.code), 説明=\(niError.localizedDescription)")
        
        switch niError.code {
        case -5884: // NIERROR_USER_DID_NOT_ALLOW
            if isPermissionTest {
                handleNIPermissionDenied()
            } else {
                DispatchQueue.main.async {
                    self.niPermissionError = "Nearby Interaction（UWB）の許可が必要です。設定アプリで許可してください。"
                }
            }
        case -5885: // NIERROR_RESOURCE_USAGE_TIMEOUT
            DispatchQueue.main.async {
                self.niPermissionError = "UWB機能がタイムアウトしました。再試行してください。"
                if isPermissionTest {
                    self.niPermissionStatus = "タイムアウト"
                }
            }
            logger.error("NIリソース使用タイムアウト")
        case -5886: // NIERROR_ACTIVE_SESSION_LIMIT_EXCEEDED
            DispatchQueue.main.async {
                self.niPermissionError = "同時に実行できるUWBセッション数を超えました。"
                if isPermissionTest {
                    self.niPermissionStatus = "制限超過"
                }
            }
            logger.error("アクティブセッション制限を超過")
        default:
            DispatchQueue.main.async {
                self.niPermissionError = "UWB機能でエラーが発生しました: \(niError.localizedDescription)"
                if isPermissionTest {
                    self.niPermissionStatus = "エラー"
                }
            }
            logger.error("NISession未知のエラー: \(error)")
        }
        
        // 許可テスト用セッションをクリーンアップ
        if isPermissionTest {
            permissionTestSession?.invalidate()
            permissionTestSession = nil
        }
    }
    
    private func handleNIPermissionGranted() {
        logger.info("✅ Nearby Interaction許可が実際に承認されました")
        
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可済み"
            self.niPermissionError = nil
        }
        
        // 許可テスト用セッションをクリーンアップ
        permissionTestSession?.invalidate()
        permissionTestSession = nil
    }
    
    private func handleNIPermissionDenied() {
        logger.error("❌ Nearby Interaction許可が拒否されました")
        
        DispatchQueue.main.async {
            self.niPermissionStatus = "拒否"
            self.niPermissionError = "Nearby Interaction（UWB）の許可が拒否されました。設定アプリのプライバシー > 近くの機器との連携から許可してください。"
        }
        
        // 許可テスト用セッションをクリーンアップ
        permissionTestSession?.invalidate()
        permissionTestSession = nil
    }
    
    // MARK: - 認証エラー処理
    
    private func handleAuthenticationError(for device: UWBDevice) {
        logger.info("🔐 認証エラー処理開始: \(device.name)")
        
        // 現在の接続を切断して再接続を試行
        centralManager?.cancelPeripheralConnection(device.peripheral)
        
        // 少し待ってから再接続を試行
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.logger.info("🔄 認証エラー後の再接続試行: \(device.name)")
            self.centralManager?.connect(device.peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ])
        }
        
        // デバイス状態をリセット
        DispatchQueue.main.async {
            device.status = .discovered
            device.distance = nil
            self.isInSecureBubble = false
            self.previousSecureBubbleStatus = false
        }
        
        // NISessionもクリーンアップ
        if let session = niSessions[device.uniqueID] {
            session.invalidate()
            niSessions.removeValue(forKey: device.uniqueID)
        }
        accessoryConfigurations.removeValue(forKey: device.uniqueID)
        
        updateConnectionStatus()
    }
    
    // MARK: - 再ペアリング処理管理
    
    private func startRepairProcess(for device: UWBDevice, error: Error) {
        let deviceID = device.uniqueID
        
        // 再ペアリングが必要かエラー内容から判定
        guard shouldAttemptRepair(for: error) else {
            return
        }
        
        // 既存のタイマーがあれば停止
        stopRepairProcess(for: device)
        
        // 再試行回数を初期化（1台限定）
        repairAttempts[deviceID] = 0
        lastRepairTime = Date()
        
        DispatchQueue.main.async {
            self.isRepairing = true
            self.repairAttemptCount += 1
        }
        
        // バックグラウンドモードの場合は単一デバイス変数に設定
        if isBackgroundMode {
            repairingDeviceID = deviceID
            logger.info("🔄 バックグラウンドで再ペアリング開始: \(device.name)")
            
            // デバッグ通知: バックグラウンド再ペアリング開始
            sendUWBPairingDebugNotification(
                title: "🔄 再ペアリング開始",
                message: "バックグラウンドで再接続を試みています",
                deviceName: device.name
            )
        } else {
            logger.info("🔄 フォアグラウンドで再ペアリング開始: \(device.name)")
        }
        
        // 即座に再ペアリング試行（固定遅延）
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
            self.attemptNISessionRepair(for: device)
        }
    }
    
    private func shouldAttemptRepair(for error: Error) -> Bool {
        let nsError = error as NSError
        
        // 再ペアリングを試行しないエラーコード
        switch nsError.code {
        case -5884: // NIERROR_USER_DID_NOT_ALLOW
            return false // ユーザーが許可を拒否した場合は再試行しない
        case -5886: // NIERROR_ACTIVE_SESSION_LIMIT_EXCEEDED
            return true // セッション制限の場合は再試行する
        case -5885: // NIERROR_RESOURCE_USAGE_TIMEOUT
            return true // タイムアウトの場合は再試行する
        case -1: // カスタムエラー（Bluetooth切断など）
            return true
        default:
            return true // その他のエラーは再試行する
        }
    }
    
    private func attemptNISessionRepair(for device: UWBDevice) {
        let deviceID = device.uniqueID
        
        logger.info("🔧 再ペアリング開始診断: \(device.name)")
        logger.info("   - デバイスID: \(deviceID)")
        logger.info("   - Bluetooth状態: \(device.peripheral.state.rawValue)")
        logger.info("   - デバイスステータス: \(device.status.rawValue)")
        logger.info("   - バックグラウンドモード: \(self.isBackgroundMode)")
        
        // 設定データの確認
        guard let configuration = self.accessoryConfigurations[deviceID] else {
            logger.error("❌ 設定データなし - 再ペアリング中止")
            stopRepairProcess(for: device)
            return
        }
        logger.info("✅ 設定データ確認完了")
        
        // デバイスの基本状態チェック
        guard self.discoveredDevices.contains(where: { $0.uniqueID == deviceID }) else {
            logger.error("❌ デバイスリストにデバイスなし - 再ペアリング中止")
            stopRepairProcess(for: device)
            return
        }
        
        let currentAttempt = repairAttempts[deviceID, default: 0] + 1
        logger.info("🔄 再ペアリング試行 #\(currentAttempt): \(device.name)")
        
        // バックグラウンドモードの場合は、このrepair試行用にbackgroundTaskを開始
        let repairBackgroundTaskID: UIBackgroundTaskIdentifier
        if isBackgroundMode {
            repairBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "NI Session Repair #\(currentAttempt)") {
                self.logger.warning("⚠️ 再ペアリングバックグラウンドタスクの有効期限切れ")
            }
            logger.info("🔵 再ペアリング用バックグラウンドタスク開始: \(repairBackgroundTaskID.rawValue)")
        } else {
            repairBackgroundTaskID = .invalid
        }
        
        // デバイスが切断されている場合は先にBluetooth再接続を試行
        if device.peripheral.state != .connected {
            logger.warning("⚠️ Bluetooth未接続 - 再接続を試行")
            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ]
            centralManager?.connect(device.peripheral, options: options)
            // 再接続待ちのため、少し後に再ペアリングを再試行
            scheduleNextRepairAttempt(for: device, delay: 5.0)
            
            // バックグラウンドタスクを終了
            if repairBackgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(repairBackgroundTaskID)
            }
            return
        }
        
        logger.info("✅ Bluetooth接続確認完了")
        
        // 既存のNISessionをクリーンアップ
        if let existingSession = niSessions[deviceID] {
            logger.info("🗑️ 既存NISession無効化")
            existingSession.invalidate()
        }
        
        // NISessionの再作成を試行
        logger.info("🆕 新しいNISession作成")
        let newSession = NISession()
        newSession.delegate = self
        niSessions[deviceID] = newSession
        
        // バックグラウンドモードの場合は特別な設定を適用
        if self.isBackgroundMode {
            setupSessionForBackgroundMode(newSession)
        }
        
        // 設定でセッションを実行
        logger.info("▶️ NISession.run()実行")
        newSession.run(configuration)
        
        logger.info("🔄 NISession再開始完了: \(device.name)")
        logger.info("   👉 次のステップ: session(_:didGenerateShareableConfigurationData:)の呼び出し待ち")
        
        // 試行回数を更新（次の試行のために）
        repairAttempts[deviceID] = currentAttempt
        
        // 成功の可能性があるので、少し待ってから結果を確認
        let verificationDelay: TimeInterval = self.isBackgroundMode ? 5.0 : 3.0
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + verificationDelay) {
            self.verifyRepairSuccess(for: device)
            
            // バックグラウンドタスクを終了
            if repairBackgroundTaskID != .invalid {
                self.logger.info("🔵 再ペアリング用バックグラウンドタスク終了: \(repairBackgroundTaskID.rawValue)")
                UIApplication.shared.endBackgroundTask(repairBackgroundTaskID)
            }
        }
    }
    
    private func setupSessionForBackgroundMode(_ session: NISession) {
        // バックグラウンドモード用の最適化設定
        logger.info("バックグラウンドモード用NISession設定")
        // 必要に応じて特別な設定を追加
    }
    
    // 🔧 修正: 再ペアリング成功後は単に状態を更新するだけ
    private func ensureDistanceMeasurementStarted(for device: UWBDevice) {
        let deviceID = device.uniqueID
        
        logger.info("✅ 再ペアリング完了: NISessionは既に実行中: \(device.name)")
        
        // 🔧 重要: デバイス状態はconnectedのままにする
        // ranging状態への変更は、accessoryUwbDidStartメッセージを受信した時に行う
        // これにより、didGenerateShareableConfigurationDataで通知が送信されるのを防ぐ
        DispatchQueue.main.async {
            if device.status != .ranging {
                device.status = DeviceStatus.connected
            }
        }
        
        // 🔧 重要: 再ペアリング後は追加のメッセージ送信不要
        // NISessionは既にrun()されており、didGenerateShareableConfigurationDataで
        // configureAndStartメッセージが送信されるため、ここでは何もしない
        
        // デバイス情報は保存しておく
        if accessoryConfigurations[deviceID] != nil {
            saveDeviceInfo(device)
        }
        
        updateConnectionStatus()
        
        logger.info("ℹ️ 距離データはNISessionのdidUpdateで自動的に受信されます")
    }
    
    // 距離計測開始の確認とリトライ処理
    private func verifyAndStartDistanceMeasurement(for device: UWBDevice, retryCount: Int) {
        let maxRetries = 5
        let retryInterval: TimeInterval = 3.0
        
        logger.info("📡 距離計測状態確認 (試行 \(retryCount + 1)/\(maxRetries)): \(device.name)")
        
        // デバイスの状態を確認
        guard device.peripheral.state == .connected else {
            logger.warning("⚠️ デバイス未接続 - 距離計測開始中止: \(device.name)")
            return
        }
        
        // 距離データが取得できているか確認
        if device.distance != nil {
            logger.info("✅ 距離計測成功: \(device.name) - \(String(format: "%.2f", device.distance!))m")
            
            // デバッグ通知: 距離計測開始成功
            sendUWBPairingDebugNotification(
                title: "📏 距離計測開始",
                message: "距離: \(String(format: "%.2f", device.distance!))m",
                deviceName: device.name
            )
            return
        }
        
        // デバイスがrangingステータスになっているか確認
        if device.status == .ranging {
            logger.info("📊 ranging中だが距離データなし - 端末が範囲外の可能性")
            
            // 範囲外の可能性があるため、もう少し待つ
            if retryCount < maxRetries {
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + retryInterval * 2) {
                    self.verifyAndStartDistanceMeasurement(for: device, retryCount: retryCount + 1)
                }
            } else {
                logger.warning("⚠️ 距離計測タイムアウト - 端末が範囲外（10m以上）の可能性: \(device.name)")
                
                // デバッグ通知: 距離計測タイムアウト
                sendUWBPairingDebugNotification(
                    title: "⚠️ 距離計測タイムアウト",
                    message: "端末が範囲外（10m以上）の可能性があります",
                    deviceName: device.name
                )
            }
            return
        }
        
        // まだrangingステータスになっていない場合、リトライ
        if retryCount < maxRetries {
            logger.info("⏳ 距離計測開始待機中... (\(retryCount + 1)/\(maxRetries))")
            
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + retryInterval) {
                self.verifyAndStartDistanceMeasurement(for: device, retryCount: retryCount + 1)
            }
        } else {
            logger.error("❌ 距離計測開始失敗 - タイムアウト: \(device.name)")
            
            // デバッグ通知: 距離計測開始失敗
            sendUWBPairingDebugNotification(
                title: "❌ 距離計測開始失敗",
                message: "NISessionが距離データを生成していません",
                deviceName: device.name
            )
            
            // 🔧 修正: 再ペアリングは呼ばない（無限ループ防止）
            // 距離データが来ないのは、範囲外か、デバイス側の問題の可能性が高い
            // 本当のNISessionエラーが発生した時のみ、session(_:didInvalidateWith:)で
            // 自動的に再ペアリングが開始される
            logger.info("ℹ️ NISessionエラーが発生した場合は自動的に再ペアリングされます")
        }
    }
    
    private func verifyRepairSuccess(for device: UWBDevice) {
        let deviceID = device.uniqueID
        
        // デバイス存在確認
        guard self.discoveredDevices.contains(where: { $0.uniqueID == deviceID }) else {
            stopRepairProcess(for: device)
            return
        }
        
        // セッションがアクティブで、デバイスが適切な状態かチェック
        let sessionExists = self.niSessions[deviceID] != nil
        let bluetoothConnected = device.peripheral.state == .connected
        
        if sessionExists && bluetoothConnected {
            // 成功と判定
            logger.info("✅ 再ペアリング成功: \(device.name)")
            
            // バックグラウンドの場合は成功通知を送信
            if isBackgroundMode {
                sendUWBPairingDebugNotification(
                    title: "✅ 再ペアリング成功",
                    message: "バックグラウンドで再接続に成功しました",
                    deviceName: device.name
                )
            }
            
            // 🔧 修正: 再ペアリング成功後に距離計測を自動開始
            ensureDistanceMeasurementStarted(for: device)
            
            stopRepairProcess(for: device)
            
            DispatchQueue.main.async {
                let shouldStop = self.isBackgroundMode ? self.repairAttempts.isEmpty : self.repairTimers.isEmpty
                if shouldStop {
                    self.isRepairing = false
                }
            }
        } else {
            // 失敗と判定、次の試行をスケジュール
            scheduleNextRepairAttempt(for: device)
        }
    }
    
    private func scheduleNextRepairAttempt(for device: UWBDevice, delay: TimeInterval? = nil) {
        let deviceID = device.uniqueID
        let currentAttempts = repairAttempts[deviceID, default: 0] + 1
        repairAttempts[deviceID] = currentAttempts
        
        // 最大試行回数をチェック
        if currentAttempts >= maxRepairAttempts {
            logger.warning("⚠️ 再ペアリング最大試行回数に到達: \(device.name)")
            
            // バックグラウンドの場合は失敗通知を送信
            if isBackgroundMode {
                sendUWBPairingDebugNotification(
                    title: "⚠️ 再ペアリング失敗",
                    message: "最大試行回数(\(maxRepairAttempts)回)に到達しました",
                    deviceName: device.name
                )
            }
            
            stopRepairProcess(for: device)
            return
        }
        
        // 指数バックオフで待機時間を計算
        // バックグラウンドでは30秒制限を考慮して短い間隔に設定
        let backoffMultiplier = self.isBackgroundMode ? 1.0 : 1.0
        let calculatedDelay = baseRepairInterval * pow(2.0, Double(currentAttempts - 1)) * backoffMultiplier
        
        // バックグラウンドでは短い最大間隔を設定（バックグラウンドタスクの30秒制限を考慮）
        let effectiveMaxInterval = self.isBackgroundMode ? 20.0 : maxRepairInterval  // BG: 20秒, FG: 60秒
        let waitTime = delay ?? min(effectiveMaxInterval, calculatedDelay)
        
        // バックグラウンドでのタイマー実行を改善
        if self.isBackgroundMode {
            // バックグラウンドタスクとして実行
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + waitTime) {
                self.attemptNISessionRepair(for: device)
            }
        } else {
            // フォアグラウンドでは通常のタイマーを使用
            let timer = Timer.scheduledTimer(withTimeInterval: waitTime, repeats: false) { _ in
                self.attemptNISessionRepair(for: device)
            }
            repairTimers[deviceID] = timer
        }
    }
    
    private func stopRepairProcess(for device: UWBDevice) {
        let deviceID = device.uniqueID
        
        // タイマーを停止（フォアグラウンドの場合のみ）
        if !isBackgroundMode {
            repairTimers[deviceID]?.invalidate()
            repairTimers.removeValue(forKey: deviceID)
        }
        
        // バックグラウンド再ペアリング対象からも削除（1台限定）
        if repairingDeviceID == deviceID {
            repairingDeviceID = nil
        }
        
        // 試行回数をリセット
        repairAttempts.removeValue(forKey: deviceID)
        
        // 全ての再ペアリングが終了したかチェック（1台限定）
        DispatchQueue.main.async {
            let hasForegroundRepairs = !self.repairTimers.isEmpty
            let hasBackgroundRepairs = self.repairingDeviceID != nil
            
            if !hasForegroundRepairs && !hasBackgroundRepairs {
                self.isRepairing = false
            }
        }
    }
    
    private func stopAllRepairProcesses() {
        // 1台限定の場合、接続済みデバイスがあればそれを停止
        if let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) {
            stopRepairProcess(for: connectedDevice)
        }
        
        // 全ての再ペアリング関連データをクリア（1台限定）
        repairingDeviceID = nil
        lastRepairTime = Date.distantPast
        
        DispatchQueue.main.async {
            self.isRepairing = false
            self.repairAttemptCount = 0
        }
    }
    
    // MARK: - TaskManager連携
    
    func setTaskManager(_ taskManager: EventKitTaskManager) {
        self.taskManager = taskManager
        logger.info("📱 TaskManager連携完了")
    }
    

    
    // デバッグ情報取得用のメソッド
    func hasNISession(for deviceID: Int) -> Bool {
        return niSessions[deviceID] != nil
    }
    
    func hasConfiguration(for deviceID: Int) -> Bool {
        return accessoryConfigurations[deviceID] != nil
    }
    
    private func adjustRepairProcessesForForeground() {
        // フォアグラウンドモードでは再ペアリング間隔を短縮（1台限定）
        for (deviceID, timer) in repairTimers {
            timer.invalidate()  // 既存のタイマーを停止
            
            if let device = findDevice(uniqueID: deviceID) {
                // より短い間隔で再スケジュール
                let shortDelay: TimeInterval = 1.0
                
                let newTimer = Timer.scheduledTimer(withTimeInterval: shortDelay, repeats: false) { _ in
                    self.attemptNISessionRepair(for: device)
                }
                repairTimers[deviceID] = newTimer
            }
        }
    }
    
    private func adjustRepairProcessesForBackground() {
        // バックグラウンドモードでは再ペアリング間隔を延長（1台限定）
        logger.info("バックグラウンドモード用に再ペアリング処理を調整")
        
        // すべての再ペアリングプロセスで次回の間隔を長くする
        // （実際の調整は次回の scheduleNextRepairAttempt で行われる）
    }
    
    // MARK: - バックグラウンド処理管理
    
    private func setupBackgroundProcessing() {
        // アプリ状態変化の監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // バックグラウンドタスクの登録
        registerBackgroundTasks()
        
        logger.info("バックグラウンド処理の設定完了")
    }
    
    // MARK: - 位置情報サービスとジオフェンシング
    
    private func setupLocationServices() {
        locationManager_geo.delegate = self
        locationManager_geo.desiredAccuracy = kCLLocationAccuracyBest
        locationManager_geo.allowsBackgroundLocationUpdates = true
        locationManager_geo.pausesLocationUpdatesAutomatically = false
        locationManager_geo.showsBackgroundLocationIndicator = false
        
        // 位置情報許可状態をチェック
        updateLocationPermissionStatus()
        
        logger.info("✅ 位置情報サービスの設定完了")
        logger.info("📍 現在の位置情報許可状態: \(self.locationPermissionStatus)")
    }
    
    private func loadHomeLocation() {
        if let data = UserDefaults.standard.data(forKey: homeLocationKey),
           let coordinateData = try? JSONDecoder().decode(CoordinateData.self, from: data) {
            homeCoordinate = coordinateData.coordinate
            homeLocationSet = true
            logger.info("保存された自宅位置を読み込み: \(coordinateData.latitude), \(coordinateData.longitude)")
            
            // 半径を読み込み（デフォルト: 100m）
            if let savedRadius = userDefaults.object(forKey: "homeRadius") as? Double {
                homeRadius = savedRadius
                logger.info("保存された半径を読み込み: \(savedRadius)m")
            }
            
            // デバッグ通知設定を読み込み（デフォルト: true）
            if userDefaults.object(forKey: "geofenceDebugNotificationEnabled") != nil {
                geofenceDebugNotificationEnabled = userDefaults.bool(forKey: "geofenceDebugNotificationEnabled")
            }
            
            // UWBペアリングデバッグ通知設定を読み込み（デフォルト: true）
            if userDefaults.object(forKey: "uwbPairingDebugNotificationEnabled") != nil {
                uwbPairingDebugNotificationEnabled = userDefaults.bool(forKey: "uwbPairingDebugNotificationEnabled")
            }
            
            // ジオフェンス監視を設定
            setupGeofencing()
        }
    }
    
    func setHomeLocation(_ coordinate: CLLocationCoordinate2D) {
        homeCoordinate = coordinate
        homeLocationSet = true
        
        // 保存
        let coordinateData = CoordinateData(coordinate: coordinate)
        if let data = try? JSONEncoder().encode(coordinateData) {
            UserDefaults.standard.set(data, forKey: homeLocationKey)
        }
        
        // ジオフェンシングを設定
        setupGeofencing()
        
        logger.info("自宅位置を設定: \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    /// オーバーロード版: address と radius も設定
    func setHomeLocation(coordinate: CLLocationCoordinate2D, address: String, radius: Double) {
        logger.info("🏠 自宅位置設定: \(address) (半径: \(radius)m)")
        
        // 座標と半径を設定
        homeCoordinate = coordinate
        homeRadius = radius
        homeLocationSet = true
        
        // 座標を保存（既存の形式）
        let coordinateData = CoordinateData(coordinate: coordinate)
        if let data = try? JSONEncoder().encode(coordinateData) {
            UserDefaults.standard.set(data, forKey: homeLocationKey)
        }
        
        // 追加情報も保存
        userDefaults.set(address, forKey: "homeAddress")
        userDefaults.set(radius, forKey: "homeRadius")
        
        // ジオフェンシング監視を設定
        setupGeofencing()
        
        logger.info("✅ ジオフェンス設定完了")
    }
    
    func requestLocationPermission() {
        locationManager_geo.requestAlwaysAuthorization()
    }
    
    private func updateLocationPermissionStatus() {
        let status = locationManager_geo.authorizationStatus
        DispatchQueue.main.async {
            switch status {
            case .notDetermined:
                self.locationPermissionStatus = "未設定"
            case .denied:
                self.locationPermissionStatus = "拒否"
            case .restricted:
                self.locationPermissionStatus = "制限中"
            case .authorizedWhenInUse:
                self.locationPermissionStatus = "使用中のみ許可"
            case .authorizedAlways:
                self.locationPermissionStatus = "常に許可"
                self.setupGeofencing()
            @unknown default:
                self.locationPermissionStatus = "不明"
            }
        }
    }
    
    private func setupGeofencing() {
        logger.info("🔧 setupGeofencing 呼び出し")
        logger.info("   自宅位置設定: \(self.homeCoordinate != nil ? "✅" : "❌")")
        logger.info("   位置情報許可: \(self.locationPermissionStatus)")
        
        guard let homeCoordinate = homeCoordinate else {
            logger.warning("⚠️ ジオフェンシング設定不可: 自宅位置未設定")
            return
        }
        
        guard locationManager_geo.authorizationStatus == .authorizedAlways else {
            logger.warning("⚠️ ジオフェンシング設定不可: 位置情報が「常に許可」ではありません")
            logger.warning("   現在の許可状態: \(self.locationPermissionStatus)")
            logger.warning("   設定アプリで「常に許可」に変更してください")
            return
        }
        
        // 既存の監視を停止
        locationManager_geo.monitoredRegions.forEach { region in
            logger.info("🛑 既存のジオフェンス監視を停止: \(region.identifier)")
            locationManager_geo.stopMonitoring(for: region)
        }
        
        // 標準のジオフェンシングを設定
        setupStandardGeofencing(coordinate: homeCoordinate)
    }
    
    private func setupStandardGeofencing(coordinate: CLLocationCoordinate2D) {
        let homeRegion = CLCircularRegion(
            center: coordinate,
            radius: homeRadius,
            identifier: "home"
        )
        homeRegion.notifyOnEntry = true
        homeRegion.notifyOnExit = true
        
        locationManager_geo.startMonitoring(for: homeRegion)
        logger.info("従来のジオフェンシング設定完了 (半径: \(self.homeRadius)m)")
        
        // 現在の状態を即座に確認
        locationManager_geo.requestState(for: homeRegion)
        logger.info("ジオフェンス状態確認リクエスト送信")
        
        DispatchQueue.main.async {
            self.geofencingEnabled = true
            self.geofencingMonitoring = true // 監視も有効化
        }
    }
    
    private func registerBackgroundTasks() {
        // UWBバックグラウンド処理タスクの登録
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier_uwb,
            using: nil
        ) { task in
            self.handleBackgroundMaintenanceTask(task: task as! BGProcessingTask)
        }
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("🟡 アプリがバックグラウンドに移行開始")
        
        DispatchQueue.main.async {
            self.isBackgroundMode = true
            self.logger.info("🟢 isBackgroundMode = true に設定完了")
        }
        
        logger.info("🟢 アプリがバックグラウンドに移行完了")
        
        // 自宅内のみバックグラウンド処理を有効化
        if isAtHome {
            // バックグラウンドタスクの開始
            beginBackgroundTask()
            
            // バックグラウンド用の処理に移行
            transitionToBackgroundMode()
            
            // 5分後目安でバックグラウンドタスクをスケジュール
            scheduleUWBBackgroundTask()
        } else {
            logger.info("Skip background setup: not at home")
            endBackgroundTask()
            stopBackgroundHeartbeat()
        }
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("🟡 アプリがフォアグラウンドに復帰開始")
        
        DispatchQueue.main.async {
            self.isBackgroundMode = false
            self.logger.info("🟢 isBackgroundMode = false に設定完了")
        }
        
        logger.info("🟢 アプリがフォアグラウンドに復帰完了")
        
        // フォアグラウンド用の処理に復帰
        transitionToForegroundMode()
        
        // バックグラウンドタスクの終了
        endBackgroundTask()
    }
    
    @objc private func appWillTerminate() {
        logger.info("アプリが終了")
        cleanupBackgroundProcessing()
    }
    
    private func beginBackgroundTask() {
        endBackgroundTask() // 既存のタスクがあれば終了
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "UWB Connection Maintenance") {
            // 有効期限が切れた場合の処理
            self.logger.warning("バックグラウンドタスクの有効期限切れ")
            self.endBackgroundTask()
        }
        
        if backgroundTaskIdentifier != .invalid {
            logger.info("バックグラウンドタスク開始: \(self.backgroundTaskIdentifier.rawValue)")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            logger.info("バックグラウンドタスク終了: \(self.backgroundTaskIdentifier.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    private func transitionToBackgroundMode() {
        logger.info("📱 バックグラウンドモードに移行")
        
        // 自宅外では何もしない
        guard isAtHome else {
            logger.info("Skip background mode (not at home)")
            return
        }
        
        // フォアグラウンド処理の停止
        stopScanning()
        stopForegroundMonitoring()
        
        // フォアグラウンド再ペアリングプロセスを停止（1台限定）
        for timer in repairTimers.values {
            timer.invalidate()
        }
        repairTimers.removeAll()
        
        // バックグラウンド処理の開始
        startBackgroundHeartbeat()
        
        DispatchQueue.main.async {
            self.backgroundSessionActive = true
        }
        
        // リソースの最適化
        optimizeForBackgroundMode()
    }
    
    private func transitionToForegroundMode() {
        logger.info("📱 フォアグラウンドモードに復帰")
        
        // ハートビートタイマーの停止
        stopBackgroundHeartbeat()
        
        // フォアグラウンド監視の開始
        startForegroundMonitoring()
        
        // バックグラウンド再ペアリング対象をフォアグラウンド処理に移行（1台限定）
        transferBackgroundRepairToForeground()
        
        // 接続状態の復元
        restoreConnectionStateFromBackground()
        
        // NISessionの状態確認と復旧
        checkAndRestoreNISessionsOnForeground()
        
        // 再ペアリング処理の調整（フォアグラウンドモード用に間隔を短縮）
        adjustRepairProcessesForForeground()
        
        // 自動再接続の実行
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startAutoReconnection()
        }
        
        DispatchQueue.main.async {
            self.backgroundSessionActive = false
        }
    }
    
    private func transferBackgroundRepairToForeground() {
        guard let deviceID = repairingDeviceID else {
            return
        }
        
        guard let device = findDevice(uniqueID: deviceID) else {
            repairingDeviceID = nil
            return
        }
        
        logger.info("🔄 バックグラウンド→フォアグラウンド移行: \(device.name)")
        
        // フォアグラウンドでより短い間隔でスケジュール（固定遅延）
        let shortDelay: TimeInterval = 1.0
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + shortDelay) {
            self.attemptNISessionRepair(for: device)
        }
        
        // バックグラウンド再ペアリング対象をクリア
        repairingDeviceID = nil
    }
    
    private func checkAndRestoreNISessionsOnForeground() {
        guard let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) else {
            return
        }
        
        let deviceID = connectedDevice.uniqueID
        let hasNISession = niSessions[deviceID] != nil
        let hasConfiguration = accessoryConfigurations[deviceID] != nil
        
        // NISessionが不足している場合の復旧処理
        if !hasNISession && hasConfiguration && connectedDevice.peripheral.state == .connected {
            logger.info("🔄 フォアグラウンド復帰時修復: \(connectedDevice.name)")
            
            // 固定遅延で復旧処理を実行
            let delay: TimeInterval = 2.0
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
                self.attemptNISessionRepair(for: connectedDevice)
            }
        } else if connectedDevice.status == .ranging && connectedDevice.distance == nil {
            // 距離データが長期間更新されていない場合
            let delay: TimeInterval = 3.0
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
                self.attemptNISessionRepair(for: connectedDevice)
            }
        }
    }
    
    private func startBackgroundHeartbeat() {
        stopBackgroundHeartbeat()
        
        backgroundHeartbeatStartTime = Date()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { _ in
            self.performBackgroundHeartbeat()
        }
        
        logger.info("バックグラウンドハートビート開始")
    }
    
    private func stopBackgroundHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        backgroundHeartbeatStartTime = nil
        logger.info("バックグラウンドハートビート停止")
    }
    
    private func performBackgroundHeartbeat() {
        guard isBackgroundMode, isAtHome else {
            logger.info("Skip background tick (home=\(self.isAtHome), bg=\(self.isBackgroundMode))")
            return
        }
        
        // ハートビート経過時間計算
        let elapsed = backgroundHeartbeatStartTime?.timeIntervalSinceNow ?? 0
        let elapsedTimeString = String(format: " (%.1f秒経過)", abs(elapsed))
        
        // バックグラウンド時のシンプルログ
        logger.info("🕒 ハートビート\(elapsedTimeString)")
        
        // 接続済みデバイスの確認
        if let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) {
            
            // 軽量なハートビートメッセージを送信
            if connectedDevice.peripheral.state == .connected {
                let heartbeatMessage = Data([MessageId.getReserved.rawValue])
                sendDataToDevice(heartbeatMessage, device: connectedDevice)
                
                // NISessionの状態確認と再ペアリング判定
                checkAndRepairNISessionIfNeeded(for: connectedDevice)
                
                // NIセッションの有効性を確認
                let hasActiveNISession = niSessions[connectedDevice.uniqueID] != nil
                logger.info("📡 NIセッション: \(hasActiveNISession ? "有効" : "無効") | Bubble: \(self.isInSecureBubble ? "内部" : "外部")")
            }
        }
        
        // バックグラウンド再ペアリング処理（1台限定）
        processBackgroundRepair()
        
        lastBackgroundUpdate = Date()
    }
    
    private func checkAndRepairNISessionIfNeeded(for device: UWBDevice) {
        // 自宅外では修復ロジックを動かさない
        guard isAtHome else { return }
        let deviceID = device.uniqueID
        
        // NISessionが存在するか確認
        let hasNISession = niSessions[deviceID] != nil
        let shouldHaveNISession = device.status == .ranging || device.status == .paired
        
        // NISessionが必要なのに存在しない場合、または距離データが長期間更新されていない場合
        let shouldRepair = (!hasNISession && shouldHaveNISession) ||
                          (device.status == .ranging && device.distance == nil && 
                           Date().timeIntervalSince(device.lastUpdate) > 60.0)  // 60秒以上距離更新なし
        
        if shouldRepair {
            // バックグラウンド再ペアリング対象に設定（1台限定）
            repairingDeviceID = deviceID
        }
    }
    
    private func processBackgroundRepair() {
        // 自宅外では修復ロジックを動かさない
        guard isAtHome else { return }
        
        guard let deviceID = repairingDeviceID else {
            logger.info("   ℹ️ 再ペアリング対象デバイスなし")
            return
        }
        
        guard let device = findDevice(uniqueID: deviceID) else {
            logger.warning("   ⚠️ 再ペアリング対象デバイスが見つかりません")
            repairingDeviceID = nil
            return
        }
        
        let currentTime = Date()
        let minIntervalBetweenAttempts: TimeInterval = 30.0  // 30秒間隔
        let timeSinceLastAttempt = currentTime.timeIntervalSince(lastRepairTime)
        
        if timeSinceLastAttempt >= minIntervalBetweenAttempts {
            logger.info("   🔄 再ペアリング実行: \(device.name)")
            logger.info("   ⏱️ 前回実行からの経過時間: \(Int(timeSinceLastAttempt))秒")
            
            // 実行時刻を更新
            lastRepairTime = currentTime
            
            // 再ペアリング実行
            attemptNISessionRepair(for: device)
            
            // 成功・失敗に関わらず対象をクリア（次回ハートビートで再評価）
            repairingDeviceID = nil
        } else {
            let remainingTime = Int(minIntervalBetweenAttempts - timeSinceLastAttempt)
            logger.info("   ⏳ 再ペアリング待機中: あと\(remainingTime)秒")
        }
    }
    
    private func saveConnectionStateForBackground() {
        guard let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) else {
            logger.info("バックグラウンド用接続状態保存: 接続済みデバイスなし")
            UserDefaults.standard.removeObject(forKey: "background_connected_device")
            return
        }
        
        let deviceState: [String: Any] = [
            "identifier": connectedDevice.peripheral.identifier.uuidString,
            "uniqueID": connectedDevice.uniqueID,
            "name": connectedDevice.name,
            "status": connectedDevice.status.rawValue
        ]
        
        UserDefaults.standard.set(deviceState, forKey: "background_connected_device")
        logger.info("バックグラウンド用接続状態保存: \(connectedDevice.name)")
    }
    
    private func restoreConnectionStateFromBackground() {
        guard let savedState = UserDefaults.standard.dictionary(forKey: "background_connected_device") else {
            logger.info("バックグラウンド用接続状態復元: 保存された状態なし")
            return
        }
        
        guard let _ = savedState["identifier"] as? String,
              let uniqueID = savedState["uniqueID"] as? Int,
              let name = savedState["name"] as? String else {
            logger.info("バックグラウンド用接続状態復元: 不正なデータ")
            return
        }
        
        logger.info("バックグラウンド用接続状態復元: \(name)")
        
        // デバイスが現在のリストに存在するかチェック
        if let existingDevice = discoveredDevices.first(where: { $0.uniqueID == uniqueID }) {
            // 状態を更新
            if existingDevice.peripheral.state == .connected {
                DispatchQueue.main.async {
                    existingDevice.status = .connected
                }
                logger.info("デバイス状態復元完了: \(existingDevice.name)")
            } else {
                logger.info("Bluetooth未接続のため状態復元スキップ: \(existingDevice.name)")
            }
        } else {
            logger.info("デバイスが現在のリストに存在しない: \(name)")
        }
    }
    
    private func scheduleBackgroundTask() {
        // 既存APIは後方互換のため残すが、自宅内のみ60秒でスケジュール
        guard isAtHome else {
            logger.info("Skip scheduling legacy BGTask (not at home)")
            return
        }
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier_uwb)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("レガシーBGタスクをスケジュール(60s)")
        } catch {
            logger.error("レガシーBGタスクのスケジュールに失敗: \(error)")
        }
    }

    // UWB専用BGタスクスケジューラ（指数バックオフ方式）
    // 初回: 1分 → 2分 → 4分 → 8分 → 16分 → 32分 → 最大60分
    private func scheduleUWBBackgroundTask(interval: TimeInterval? = nil) {
        guard isAtHome else {
            logger.info("Skip scheduling UWB BGTask (not at home)")
            return
        }
        
        // 明示的に間隔が指定されている場合はそれを使用（リセット用）
        let actualInterval: TimeInterval
        if let interval = interval {
            actualInterval = interval
            currentBGTaskInterval = interval
        } else {
            actualInterval = currentBGTaskInterval
        }
        
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier_uwb)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: actualInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            let minutes = Int(actualInterval / 60)
            let seconds = Int(actualInterval.truncatingRemainder(dividingBy: 60))
            if minutes > 0 {
                logger.info("📅 UWB BGタスクをスケジュール: \(minutes)分\(seconds > 0 ? "\(seconds)秒" : "")")
            } else {
                logger.info("📅 UWB BGタスクをスケジュール: \(seconds)秒")
            }
        } catch {
            logger.error("❌ UWB BGタスクのスケジュールに失敗: \(error)")
        }
    }
    
    /// BGタスク間隔を次の値に増やす（指数バックオフ）
    private func increaseBackgroundTaskInterval() {
        let nextInterval = min(currentBGTaskInterval * 2, maxBGTaskInterval)
        if nextInterval != currentBGTaskInterval {
            currentBGTaskInterval = nextInterval
            logger.info("⏱️ BGタスク間隔を延長: \(Int(self.currentBGTaskInterval / 60))分")
        } else {
            logger.info("⏱️ BGタスク間隔は最大値(\(Int(self.maxBGTaskInterval / 60))分)に到達")
        }
    }
    
    /// BGタスク間隔を初期値にリセット
    private func resetBackgroundTaskInterval() {
        if currentBGTaskInterval != minBGTaskInterval {
            currentBGTaskInterval = minBGTaskInterval
            logger.info("🔄 BGタスク間隔をリセット: \(Int(self.minBGTaskInterval / 60))分")
        }
    }

    private func cancelUWBBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier_uwb)
        logger.info("UWB BGタスクをキャンセル")
    }
    
    private func handleBackgroundMaintenanceTask(task: BGProcessingTask) {
        let currentInterval = Int(currentBGTaskInterval / 60)
        logger.info("🔔 バックグラウンドメンテナンスタスク開始（間隔: \(currentInterval)分）")
        
        // 自宅外なら即終了し、次回は自宅内で再スケジュール
        guard isAtHome else {
            logger.info("⚠️ 自宅外のためBGタスク実行をスキップ")
            task.setTaskCompleted(success: true)
            return
        }
        
        logger.info("🏠 自宅内でのUWB再ペアリングチェック実行")
        
        task.expirationHandler = {
            self.logger.warning("バックグラウンドメンテナンスタスク期限切れ")
            self.isProcessingBackgroundTask = false
            task.setTaskCompleted(success: false)
        }
        
        isProcessingBackgroundTask = true
        
        // UWB再接続サイクルを試行（スキャン開始/NI修復）
        ensureBackgroundUWBRecovery()
        
        // バックグラウンドでの保守作業を実行
        performBackgroundMaintenance { success in
            self.isProcessingBackgroundTask = false
            task.setTaskCompleted(success: success)
            
            // 成功した場合は間隔を延長（指数バックオフ）
            if success {
                self.increaseBackgroundTaskInterval()
            } else {
                // 失敗時は間隔をリセット
                self.resetBackgroundTaskInterval()
            }
            
            // 次のタスクをスケジュール
            self.scheduleUWBBackgroundTask()
        }
    }

    // 自宅内でのUWB復旧処理（BGタスク起床時にも呼ぶ）
    private func ensureBackgroundUWBRecovery() {
        guard isAtHome else { return }
        
        logger.info("🔧 UWB復旧処理開始")
        
        // 接続済みデバイスがない場合はスキャン開始
        if !isScanning && !hasConnectedDevices {
            logger.info("📡 接続済みデバイスなし - スキャン開始")
            startScanning()
        }
        
        // 接続済みデバイスがある場合は再ペアリングをチェック
        if let device = discoveredDevices.first(where: { $0.status == .connected || $0.status == .paired || $0.status == .ranging }) {
            logger.info("🔌 接続済みデバイス検出: \(device.name)")
            
            let deviceID = device.uniqueID
            let hasNISession = niSessions[deviceID] != nil
            let hasDistance = device.distance != nil
            
            logger.info("   - ステータス: \(device.status.rawValue)")
            logger.info("   - NISession: \(hasNISession ? "有" : "無")")
            logger.info("   - 距離データ: \(hasDistance ? "有" : "無")")
            
            // 再ペアリングが必要かチェック
            checkAndRepairNISessionIfNeeded(for: device)
            
            // 再ペアリング実行
            processBackgroundRepair()
        } else {
            logger.info("⚠️ 接続済みデバイスなし")
        }
    }
    
    private func performBackgroundMaintenance(completion: @escaping (Bool) -> Void) {
        logger.info("バックグラウンドメンテナンス実行")
        
        var maintenanceTasks: [() -> Void] = []
        
        // 1. 期限切れデバイスのクリーンアップ
        maintenanceTasks.append {
            self.cleanupTimeoutDevices()
        }
        
        // 2. 保存されたデバイス情報の整理
        maintenanceTasks.append {
            self.cleanupSavedDevices()
        }
        
        // 3. ログの整理（必要に応じて）
        maintenanceTasks.append {
            self.cleanupLogs()
        }
        
        // メンテナンスタスクを順次実行
        let dispatchGroup = DispatchGroup()
        
        for task in maintenanceTasks {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .background).async {
                task()
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.logger.info("バックグラウンドメンテナンス完了")
            completion(true)
        }
    }
    
    private func cleanupSavedDevices() {
        var savedDevices = loadSavedDevices()
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        // 1週間以上前のデバイス情報を削除
        savedDevices.removeAll { $0.savedDate < oneWeekAgo }
        
        if let encoded = try? JSONEncoder().encode(savedDevices) {
            UserDefaults.standard.set(encoded, forKey: savedDevicesKey)
            logger.info("古いデバイス情報をクリーンアップ")
        }
    }
    
    private func cleanupLogs() {
        // ログファイルのクリーンアップ（実装は必要に応じて）
        logger.info("ログクリーンアップ実行")
    }
    
    // Bubble状態変化を記録
    private func recordBubbleStateChange(isInBubble: Bool) {
        let now = Date()
        
        if !isInBubble {
            // Bubble外になった場合
            if currentOutsideStartTime == nil {
                currentOutsideStartTime = now
                // 休憩回数をカウント
                let calendar = Calendar.current
                if calendar.isDateInToday(now) {
                    todayBreakCount += 1
                    logger.info("📊 休憩回数カウント: \(self.todayBreakCount)")
                }
            }
        } else {
            // Bubble内に戻った場合
            if let startTime = currentOutsideStartTime {
                let session = BubbleSession(
                    startTime: startTime,
                    endTime: now,
                    duration: now.timeIntervalSince(startTime),
                    isOutside: true,
                    taskId: getCurrentTaskId()
                )
                saveBubbleSession(session)
                currentOutsideStartTime = nil
            }
        }
    }
    
    // 現在のタスクIDを取得
    private func getCurrentTaskId() -> String? {
        let todayTasks = getTasksDueUntilToday()
        return todayTasks.first { !$0.isCompleted }?.id.uuidString
    }
    
    // Bubbleセッションを保存
    private func saveBubbleSession(_ session: BubbleSession) {
        var sessions = getBubbleSessions()
        sessions.append(session)
        
        // 過去30日間のデータのみ保持
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        sessions = sessions.filter { $0.startTime >= thirtyDaysAgo }
        
        if let encoded = try? JSONEncoder().encode(sessions) {
            userDefaults.set(encoded, forKey: bubbleSessionsKey)
            logger.info("📊 Bubbleセッション保存: \(String(format: "%.1f", session.duration / 60))分 (外部)")
        }
    }
    
    // Bubbleセッションを取得
    func getBubbleSessions() -> [BubbleSession] {
        guard let data = userDefaults.data(forKey: bubbleSessionsKey),
              let sessions = try? JSONDecoder().decode([BubbleSession].self, from: data) else {
            return []
        }
        return sessions
    }
    
    // 今日の総不在時間を計算
    func getTodayTotalOutsideTime() -> TimeInterval {
        let sessions = getBubbleSessions()
        let today = Calendar.current.startOfDay(for: Date())
        let todayOutsideSessions = sessions.filter { 
            $0.isOutside && Calendar.current.isDate($0.startTime, inSameDayAs: today)
        }
        
        return todayOutsideSessions.reduce(0) { $0 + $1.duration }
    }
    
    // 今日の休憩回数を取得
    func getTodayBreakCount() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 保存されたセッションから今日の休憩回数を計算
        let sessions = getBubbleSessions()
        let todayOutsideSessions = sessions.filter { 
            $0.isOutside && calendar.isDate($0.startTime, inSameDayAs: today)
        }
        
        // 現在進行中の休憩も含める
        var breakCount = todayOutsideSessions.count
        if currentOutsideStartTime != nil && calendar.isDateInToday(Date()) {
            breakCount += 1
        }
        
        return breakCount
    }
    

    
    private func cleanupBackgroundProcessing() {
        stopBackgroundHeartbeat()
        stopForegroundMonitoring()  // フォアグラウンド監視も停止
        endBackgroundTask()
        stopAllRepairProcesses()  // 再ペアリングプロセスも停止
        
        // 通知の監視を停止
        NotificationCenter.default.removeObserver(self)
        
        logger.info("バックグラウンド処理のクリーンアップ完了")
    }
    
    // デバイス接続の最適化
    func optimizeForBackgroundMode() {
        logger.info("バックグラウンドモード用最適化実行")
        
        // アクティブでないセッションの停止
        for (deviceID, session) in niSessions {
            if let device = findDevice(uniqueID: deviceID),
               device.status != .ranging {
                session.invalidate()
                niSessions.removeValue(forKey: deviceID)
                logger.info("非アクティブセッション停止: \(device.name)")
            }
        }
        
        // 通信頻度の調整
        adjustCommunicationFrequency()
    }
    
    private func adjustCommunicationFrequency() {
        // バックグラウンドでは通信頻度を下げて電力を節約
        logger.info("通信頻度をバックグラウンド用に調整")
    }
    
    // MARK: - フォアグラウンド自動修復処理
    
    private func startForegroundMonitoring() {
        stopForegroundMonitoring()
        
        foregroundMonitorTimer = Timer.scheduledTimer(withTimeInterval: foregroundCheckInterval, repeats: true) { _ in
            self.performForegroundHealthCheck()
        }
        
        logger.info("フォアグラウンド監視開始")
    }
    
    private func stopForegroundMonitoring() {
        foregroundMonitorTimer?.invalidate()
        foregroundMonitorTimer = nil
        logger.info("フォアグラウンド監視停止")
    }
    
    private func performForegroundHealthCheck() {
        guard !isBackgroundMode else { return }
        
        guard let connectedDevice = discoveredDevices.first(where: { 
            $0.status == .connected || $0.status == .paired || $0.status == .ranging
        }) else {
            return
        }
        
        let deviceID = connectedDevice.uniqueID
        let hasNISession = niSessions[deviceID] != nil
        let hasConfiguration = accessoryConfigurations[deviceID] != nil
        let bluetoothConnected = connectedDevice.peripheral.state == .connected
        let shouldBeRanging = connectedDevice.status == .paired || connectedDevice.status == .ranging
        
        // NISessionが必要なのに存在しない場合
        if shouldBeRanging && !hasNISession && hasConfiguration && bluetoothConnected {
            logger.info("🔄 フォアグラウンド自動修復: NISession不足を検出")
            let repairError = NSError(domain: "UWBManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "フォアグラウンド自動修復"])
            startRepairProcess(for: connectedDevice, error: repairError)
            return
        }
        
        // 距離測定中だが長時間距離が更新されていない場合
        if connectedDevice.status == .ranging {
            if let lastUpdate = lastDistanceUpdateTime {
                let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
                if timeSinceLastUpdate > maxDistanceUpdateDelay {
                    logger.info("🔄 フォアグラウンド自動修復: 距離更新遅延を検出 (\(Int(timeSinceLastUpdate))秒)")
                    let repairError = NSError(domain: "UWBManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "距離更新遅延による修復"])
                    startRepairProcess(for: connectedDevice, error: repairError)
                }
            } else if connectedDevice.distance == nil {
                // 距離測定中だが距離データがない場合
                logger.info("🔄 フォアグラウンド自動修復: 距離データ不足を検出")
                let repairError = NSError(domain: "UWBManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "距離データ不足による修復"])
                startRepairProcess(for: connectedDevice, error: repairError)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension UWBManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }
        
        switch central.state {
        case .poweredOn:
            logger.info("Bluetooth準備完了")
            // 自動接続を開始（フォアグラウンドのみ）
            if !isBackgroundMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startAutoReconnection()
                }
                // フォアグラウンド監視も開始
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.startForegroundMonitoring()
                }
            }
        case .poweredOff:
            logger.error("Bluetooth無効")
            DispatchQueue.main.async {
                self.scanningError = "Bluetoothが無効です"
                self.isScanning = false
            }
        case .unauthorized:
            logger.error("Bluetooth未認証")
            DispatchQueue.main.async {
                self.scanningError = "Bluetoothの許可が必要です"
                self.isScanning = false
            }
        default:
            logger.error("Bluetooth状態不明: \(String(describing: central.state))")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            return
        }
        
        let uniqueID = peripheral.hashValue
        
        // 既存のデバイスかチェック
        if let existingDevice = findDevice(peripheral: peripheral) {
            DispatchQueue.main.async {
                existingDevice.lastUpdate = Date()
            }
            return
        }
        
        // 新しいデバイスを追加
        let newDevice = UWBDevice(peripheral: peripheral, uniqueID: uniqueID, name: name)
        
        DispatchQueue.main.async {
            self.discoveredDevices.append(newDevice)
        }
        
        logger.info("新しいデバイス発見: \(name)")
        
        // 保存されたデバイスかチェックして自動接続
        let savedDevices = loadSavedDevices()
        if savedDevices.contains(where: { $0.peripheralIdentifier == peripheral.identifier.uuidString }) {
            logger.info("保存済みデバイス発見、自動接続開始: \(name)")
            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ]
            centralManager?.connect(peripheral, options: options)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("デバイス接続成功: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.isConnecting = false
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([QorvoNIService.serviceUUID])
        
        // 自動接続が成功した場合、スキャンを停止
        let savedDevices = loadSavedDevices()
        if savedDevices.contains(where: { $0.peripheralIdentifier == peripheral.identifier.uuidString }) {
            stopScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("デバイス接続失敗: \(error?.localizedDescription ?? "Unknown error")")
        
        if let device = findDevice(peripheral: peripheral) {
            // デバッグ通知: Bluetooth接続失敗
            sendUWBPairingDebugNotification(
                title: "❌ UWB接続失敗",
                message: "Bluetooth接続に失敗しました",
                deviceName: device.name
            )
            
            DispatchQueue.main.async {
                device.status = DeviceStatus.discovered
            }
        }
        
        DispatchQueue.main.async {
            self.isConnecting = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("デバイス切断: \(peripheral.name ?? "Unknown") - エラー: \(error?.localizedDescription ?? "なし")")
        
        if let device = findDevice(peripheral: peripheral) {
            DispatchQueue.main.async {
                device.status = DeviceStatus.discovered
                device.distance = nil
                
                // Secure Bubble状態をリセット（デバイス切断時）
                self.isInSecureBubble = false
                self.previousSecureBubbleStatus = false
            }
            updateConnectionStatus()
            
            // Bluetooth切断時にScreenTime制限を自動解除
            if let screenTimeManager = screenTimeManager {
                logger.info("🔓 Bluetooth切断によりScreenTime制限を自動解除")
                screenTimeManager.disableRestrictionForSecureBubble()
            }
            
            // NISessionも無効化されている可能性があるため、再ペアリングを開始
            if niSessions[device.uniqueID] != nil {
                logger.info("デバイス切断により再ペアリングを開始: \(device.name)")
                
                // NISessionを明示的に無効化
                niSessions[device.uniqueID]?.invalidate()
                niSessions.removeValue(forKey: device.uniqueID)
                
                // 再ペアリングプロセスを開始（エラー作成）
                let disconnectionError = NSError(domain: "UWBManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bluetooth切断による再ペアリング"])
                startRepairProcess(for: device, error: disconnectionError)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension UWBManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("サービス発見エラー: \(error)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics([
                QorvoNIService.scCharacteristicUUID,
                QorvoNIService.rxCharacteristicUUID,
                QorvoNIService.txCharacteristicUUID
            ], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.error("Characteristic発見エラー: \(error)")
            return
        }
        
        guard let device = findDevice(peripheral: peripheral),
              let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case QorvoNIService.scCharacteristicUUID:
                device.scCharacteristic = characteristic
                logger.info("SC Characteristic発見")
            case QorvoNIService.rxCharacteristicUUID:
                device.rxCharacteristic = characteristic
                logger.info("RX Characteristic発見")
            case QorvoNIService.txCharacteristicUUID:
                device.txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                logger.info("TX Characteristic発見・通知有効化")
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            logger.error("データ受信エラー: \(error)")
            
            // Bluetooth認証エラーの特別処理
            if nsError.domain == "CBATTErrorDomain" && nsError.code == 5 {
                // Authentication is insufficient エラー
                logger.error("🔐 Bluetooth認証不足エラー - デバイス再接続を試行")
                
                if let device = findDevice(peripheral: peripheral) {
                    handleAuthenticationError(for: device)
                }
            }
            return
        }
        
        guard let data = characteristic.value,
              let device = findDevice(peripheral: peripheral) else { return }
        
        if characteristic.uuid == QorvoNIService.scCharacteristicUUID {
            // ペアリング処理
            handleAccessoryPaired(device: device)
        } else if characteristic.uuid == QorvoNIService.txCharacteristicUUID {
            // データ処理
            handleReceivedData(data, from: device)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("通知状態更新エラー: \(error)")
            return
        }
        
        if characteristic.isNotifying {
            logger.info("通知開始: \(characteristic.uuid)")
            
            // ペアリング開始
            if let device = findDevice(peripheral: peripheral),
               characteristic.uuid == QorvoNIService.txCharacteristicUUID,
               let scCharacteristic = device.scCharacteristic {
                peripheral.readValue(for: scCharacteristic)
            }
        }
    }
}

// MARK: - NISessionDelegate
extension UWBManager: NISessionDelegate {
    // セッションが正常に開始された場合（許可が得られた）
    func sessionWasSuspended(_ session: NISession) {
        logger.info("🟡 NISession一時停止")
        
        // 許可テスト用セッションの場合、一時停止は許可とは関係ない
        if session == permissionTestSession {
            logger.info("🔵 許可テスト用セッション一時停止")
        }
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        logger.info("🟢 NISession再開")
        
        // 許可テスト用セッションの場合、再開は許可とは関係ない
        if session == permissionTestSession {
            logger.info("🔵 許可テスト用セッション再開")
        }
    }
    
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        
        logger.info("📡 NISession設定データ生成コールバック")
        logger.info("   - データサイズ: \(shareableConfigurationData.count) bytes")
        
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            logger.info("🔵 許可テスト用セッション設定データ生成 - 許可済み")
            handleNIPermissionGranted()
            return
        }
        
        // 実際のデバイスセッションの場合も許可が得られたことを示す
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可済み"
            self.niPermissionError = nil
        }
        
        // セッションに対応するデバイスを見つける
        var targetDevice: UWBDevice?
        for (deviceID, niSession) in niSessions {
            if niSession == session {
                targetDevice = findDevice(uniqueID: deviceID)
                break
            }
        }
        
        guard let device = targetDevice else {
            logger.error("❌ 設定データ生成: デバイスが見つかりません")
            return
        }
        
        logger.info("✅ 設定データ生成: \(device.name)")
        logger.info("   - Bluetooth状態: \(device.peripheral.state.rawValue)")
        logger.info("   - デバイスステータス: \(device.status.rawValue)")
        logger.info("   - 再ペアリング中: \(self.isRepairing)")
        
        // 🔧 修正: 再ペアリング中は通知を送信しない（重複通知を防ぐ）
        // 初回ペアリング時のみ通知を送信
        if !self.isRepairing {
            sendUWBPairingDebugNotification(
                title: "🔄 UWBペアリング開始",
                message: "NIセッション設定を送信します",
                deviceName: device.name
            )
        } else {
            logger.info("ℹ️ 再ペアリング中のため、ペアリング開始通知をスキップ")
        }
        
        // 設定データを送信
        var message = Data([MessageId.configureAndStart.rawValue])
        message.append(shareableConfigurationData)
        
        logger.info("📤 configureAndStartメッセージ送信")
        sendDataToDevice(message, device: device)
        
        logger.info("✅ 共有設定データ送信完了: \(device.name)")
        logger.info("   👉 次のステップ: デバイスからのaccessoryUwbDidStart応答待ち")
    }
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            logger.info("🔵 許可テスト用セッションの距離更新")
            handleNIPermissionGranted()
            return
        }
        
        // 実際のデバイスセッションで距離更新があった場合も許可済みを示す
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可済み"
            self.niPermissionError = nil
        }
        
        // オブジェクトの詳細をログ出力（デバッグ用）
        if nearbyObjects.isEmpty {
            logger.info("📡 NISession更新: オブジェクトなし（範囲外）")
            return
        }
        
        guard let accessory = nearbyObjects.first else {
            logger.warning("⚠️ NISession更新: nearbyObjectsが空")
            return
        }
        
        // 距離データの有無を確認
        guard let distance = accessory.distance else {
            logger.info("📡 NISession更新: オブジェクト検出されたが距離データなし")
            logger.info("   - discoveryToken: \(accessory.discoveryToken != nil ? "あり" : "なし")")
            logger.info("   - direction: \(accessory.direction != nil ? "あり" : "なし")")
            return
        }
        
        // セッションに対応するデバイスを見つける
        var targetDevice: UWBDevice?
        for (deviceID, niSession) in niSessions {
            if niSession == session {
                targetDevice = findDevice(uniqueID: deviceID)
                break
            }
        }
        
        guard let device = targetDevice else {
            logger.warning("⚠️ NISession更新: デバイスが見つかりません")
            return
        }
        
        // 初回の距離データ取得時のログ
        let isFirstDistance = device.distance == nil
        if isFirstDistance {
            logger.info("🎯 初回距離データ取得成功: \(device.name) - \(String(format: "%.2f", distance))m")
        }
        
        DispatchQueue.main.async {
            device.distance = distance
            device.status = DeviceStatus.ranging
        }
        
        // 距離更新時刻を記録（フォアグラウンド監視用）
        lastDistanceUpdateTime = Date()
        
        updateConnectionStatus()
        
        // UWBで距離計測できているので、ジオフェンス監視を一時停止（初回のみ）
        if geofencingMonitoring {
            pauseGeofenceMonitoring()
        }
        
        // Secure bubble判定を実行
        checkSecureBubbleStatus(distance: distance, device: device)
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        logger.info("オブジェクト削除 理由: \(String(describing: reason))")
        
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            return
        }
        
        // セッションに対応するデバイスを見つける
        var targetDevice: UWBDevice?
        for (deviceID, niSession) in niSessions {
            if niSession == session {
                targetDevice = findDevice(uniqueID: deviceID)
                break
            }
        }
        
        guard let device = targetDevice else { return }
        
        DispatchQueue.main.async {
            device.distance = nil
        }
        updateConnectionStatus()
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        // エラーハンドリング
        handleNIError(error)
        
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            permissionTestSession = nil
            return
        }
        
        // セッションに対応するデバイスを見つけて処理
        for (deviceID, niSession) in niSessions {
            if niSession == session {
                niSessions.removeValue(forKey: deviceID)
                
                // デバイス状態をリセット
                if let device = findDevice(uniqueID: deviceID) {
                    // デバッグ通知: ペアリング切断
                    sendUWBPairingDebugNotification(
                        title: "⚠️ UWBセッション切断",
                        message: "NIセッションが無効化されました",
                        deviceName: device.name
                    )
                    
                    DispatchQueue.main.async {
                        device.distance = nil
                        if device.status == DeviceStatus.ranging {
                            device.status = DeviceStatus.connected
                        }
                        
                        // Secure Bubble状態をリセット
                        self.isInSecureBubble = false
                        self.previousSecureBubbleStatus = false
                    }
                    updateConnectionStatus()
                    
                    // UWBセッションが切断されたので、ジオフェンス監視を再開
                    resumeGeofenceMonitoring()
                    
                    // BGタスク間隔をリセット（次回の再接続を素早く試みるため）
                    resetBackgroundTaskInterval()
                    
                    // NISession切断時にScreenTime制限を自動解除
                    if let screenTimeManager = screenTimeManager {
                        logger.info("🔓 NISession切断によりScreenTime制限を自動解除")
                        screenTimeManager.disableRestrictionForSecureBubble()
                    }
                    
                    // 再ペアリング処理を開始
                    startRepairProcess(for: device, error: error)
                }
                break
            }
        }
    }
}

struct UWBSettingsView: View {
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingNIPermissionAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ヘッダー
                VStack(spacing: 16) {
                    Image(systemName: "wave.3.right.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("UWBデバイス設定")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("DWM3001CDKデバイス（1台）との通信とリアルタイム距離測定")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                
                // UWB状態表示
                if uwbManager.isUWBActive {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: uwbManager.isInSecureBubble ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
                            Text("Secure Bubble: \(uwbManager.isInSecureBubble ? "内部" : "外部")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        // バックグラウンド状態表示
                        HStack {
                            Image(systemName: uwbManager.isBackgroundMode ? "moon.circle.fill" : "sun.max.circle.fill")
                                .foregroundColor(uwbManager.isBackgroundMode ? .blue : .orange)
                            Text("動作モード: \(uwbManager.isBackgroundMode ? "バックグラウンド" : "フォアグラウンド")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        if uwbManager.backgroundSessionActive {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("バックグラウンドセッション: アクティブ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        
                        // 再ペアリング状態表示
                        if uwbManager.isRepairing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("再ペアリング中... (試行回数: \(uwbManager.repairAttemptCount))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                
                
                // 通知設定
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(uwbManager.notificationsEnabled ? .blue : .gray)
                    Text("通知")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    Toggle("", isOn: $uwbManager.notificationsEnabled)
                        .scaleEffect(0.8)
                }
                .padding(.horizontal)
                
                // UWBペアリングデバッグ通知設定
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(uwbManager.uwbPairingDebugNotificationEnabled ? .blue : .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UWBペアリング通知")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("接続開始・成功・失敗時に通知")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { uwbManager.uwbPairingDebugNotificationEnabled },
                        set: { uwbManager.setUWBPairingDebugNotification(enabled: $0) }
                    ))
                    .scaleEffect(0.8)
                }
                .padding(.horizontal)
                
                // Bluetooth状態表示
                HStack {
                    Circle()
                        .fill(bluetoothStateColor)
                        .frame(width: 12, height: 12)
                    Text(bluetoothStateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                // スキャンボタン
                Button(action: {
                    if uwbManager.isScanning {
                        uwbManager.stopScanning()
                    } else {
                        uwbManager.startScanning()
                    }
                }) {
                    HStack {
                        if uwbManager.isScanning && !uwbManager.hasConnectedDevices {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("スキャン中...")
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text("デバイスをスキャン")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(scanButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(uwbManager.bluetoothState != .poweredOn || uwbManager.isConnecting || uwbManager.hasConnectedDevices)
                .padding(.horizontal)
                
                // 接続解除ボタン（接続済みデバイスがある場合のみ表示）
                if uwbManager.hasConnectedDevices {
                    Button(action: {
                        uwbManager.disconnectAllDevices()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("デバイス切断")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                }
                
                // エラー表示
                if let error = uwbManager.scanningError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // NIPermission エラー表示
                if let niError = uwbManager.niPermissionError {
                    VStack(spacing: 8) {
                        Text(niError)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                        
                        Button("設定アプリを開く") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                
                // デバイスリスト
                if !uwbManager.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("UWBデバイス")
                                .font(.headline)
                            
                            Spacer()
                            

                        }
                        .padding(.horizontal)
                        
                        // デバッグ情報表示
                        if uwbManager.hasConnectedDevices {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🔍 診断情報")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let connectedDevice = uwbManager.discoveredDevices.first(where: { 
                                    $0.status == .connected || $0.status == .paired || $0.status == .ranging
                                }) {
                                    let deviceID = connectedDevice.uniqueID
                                    let hasNISession = uwbManager.hasNISession(for: deviceID)
                                    let hasConfiguration = uwbManager.hasConfiguration(for: deviceID)
                                    
                                    HStack {
                                        Text("• NISession:")
                                        Text(hasNISession ? "作成済み" : "なし")
                                            .foregroundColor(hasNISession ? .green : .red)
                                    }
                                    .font(.caption)
                                    
                                    HStack {
                                        Text("• 設定データ:")
                                        Text(hasConfiguration ? "受信済み" : "なし")
                                            .foregroundColor(hasConfiguration ? .green : .red)
                                    }
                                    .font(.caption)
                                    
                                    HStack {
                                        Text("• Bluetooth状態:")
                                        Text("\(connectedDevice.peripheral.state.rawValue)")
                                            .foregroundColor(connectedDevice.peripheral.state == .connected ? .green : .orange)
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        
                        // デバイスリスト（ScrollViewは除去してLazyVStackのみ使用）
                        LazyVStack(spacing: 8) {
                            ForEach(uwbManager.discoveredDevices) { device in
                                DeviceRowView(device: device, uwbManager: uwbManager)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // 下部のスペースを追加
                Spacer(minLength: 50)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("UWB設定")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    
    
    private var bluetoothStateColor: Color {
        switch uwbManager.bluetoothState {
        case .poweredOn:
            return .green
        case .poweredOff, .unauthorized:
            return .red
        default:
            return .orange
        }
    }
    
    private var bluetoothStateText: String {
        switch uwbManager.bluetoothState {
        case .poweredOn:
            return "Bluetooth準備完了"
        case .poweredOff:
            return "Bluetoothが無効です"
        case .unauthorized:
            return "Bluetooth許可が必要です"
        default:
            return "Bluetooth状態不明"
        }
    }
    
    private var scanButtonColor: Color {
        if uwbManager.bluetoothState != .poweredOn || uwbManager.isConnecting || uwbManager.hasConnectedDevices {
            return .gray
        }
        return uwbManager.isScanning ? .orange : .blue
    }
}

// デバイス行ビュー（Swipeアクションと距離表示の改善）
struct DeviceRowView: View {
    @ObservedObject var device: UWBDevice
    let uwbManager: UWBManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name)
                        .font(.headline)
                    if uwbManager.isDeviceSaved(device) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Text(device.status.rawValue)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            Spacer()
            
            // 右側に距離表示とステータス表示
            VStack(alignment: .trailing, spacing: 4) {
                if device.status == DeviceStatus.ranging, let distance = device.distance {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("\(String(format: "%.2f", distance))m")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                } else if device.status == DeviceStatus.paired || device.status == DeviceStatus.connected {
                    VStack(spacing: 4) {
                        Text("接続済み")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        // 個別切断ボタン
                        Button("切断") {
                            uwbManager.disconnectFromDevice(device)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                } else if device.status == DeviceStatus.discovered {
                    Button("接続") {
                        uwbManager.connectToDevice(device)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if device.status != DeviceStatus.discovered {
                Button("切断") {
                    uwbManager.disconnectFromDevice(device)
                }
                .tint(.red)
            }
            
            if uwbManager.isDeviceSaved(device) {
                Button("保存削除") {
                    uwbManager.removeDeviceFromSaved(device)
                }
                .tint(.orange)
            }
        }
    }
    
    private var statusColor: Color {
        switch device.status {
        case .discovered:
            return .secondary
        case .connected:
            return .blue
        case .paired:
            return .green
        case .ranging:
            return .purple
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension UWBManager {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        logger.info("位置情報許可状態変更: \(status.rawValue)")
        updateLocationPermissionStatus()
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        logger.info("🔍 ジオフェンス状態判定: \(region.identifier) - \(state == .inside ? "内部" : state == .outside ? "外部" : "不明")")
        
        if region.identifier == "home" {
            switch state {
            case .inside:
                logger.info("✅ 現在ジオフェンス内にいます")
                DispatchQueue.main.async {
                    self.isAtHome = true
                }
                handleHomeEntry()
            case .outside:
                logger.info("❌ 現在ジオフェンス外にいます")
                DispatchQueue.main.async {
                    self.isAtHome = false
                }
                handleHomeExit()
            case .unknown:
                logger.info("⚠️ ジオフェンス状態不明")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        logger.info("🏠 ジオフェンス進入: \(region.identifier)")
        
        if region.identifier == "home" {
            DispatchQueue.main.async {
                self.isAtHome = true
            }
            
            // 自宅に帰った時のUWB再接続処理
            handleHomeEntry()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        logger.info("🚪 ジオフェンス退出: \(region.identifier)")
        
        if region.identifier == "home" {
            DispatchQueue.main.async {
                self.isAtHome = false
            }
            
            // 自宅から出た時の処理
            handleHomeExit()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        logger.error("❌ ジオフェンス監視失敗: \(error)")
        DispatchQueue.main.async {
            self.geofencingEnabled = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        logger.info("✅ ジオフェンス監視開始: \(region.identifier)")
    }
    
    private func handleHomeEntry() {
        logger.info("🏠 自宅エリア進入 - UWB再接続開始")
        
        // デバッグ通知を送信
        if geofenceDebugNotificationEnabled {
            sendGeofenceDebugNotification(
                title: "🏠 ジオフェンス進入",
                message: "自宅エリアに入りました。UWB再接続を開始します。"
            )
        }
        
        // バックグラウンドアクティビティセッションを開始（iOS 17+）
        if #available(iOS 17.0, *) {
            startBackgroundActivitySession()
        }
        
        // UWBスキャンを開始（新規デバイス検出用）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.logger.info("🔄 帰宅時UWB自動接続処理開始")
            
            // スキャン中でない場合はスキャンを開始（新規デバイス用）
            if !self.isScanning {
                self.logger.info("📡 UWBスキャン開始（新規デバイス検出用）")
                self.startScanning()
            } else {
                self.logger.info("ℹ️ 既にスキャン中のため、スキャン継続")
            }
            
            // 接続済みデバイスの状態確認（ログのみ）
            if self.hasConnectedDevices {
                let connectedDevices = self.discoveredDevices.filter { 
                    $0.status == .connected || $0.status == .paired || $0.status == .ranging
                }
                
                self.logger.info("🔌 接続済みデバイス: \(connectedDevices.count)台")
                for device in connectedDevices {
                    let deviceID = device.uniqueID
                    let hasNISession = self.niSessions[deviceID] != nil
                    let hasDistance = device.distance != nil
                    
                    self.logger.info("   - \(device.name): ステータス=\(device.status.rawValue), NISession=\(hasNISession ? "有" : "無"), 距離=\(hasDistance ? "有" : "無")")
                }
                
                self.logger.info("⏰ 再ペアリングは1分後のバックグラウンドタスクで実行予定")
            }
        }
        
        // ジオフェンス内に入ったらBGタスクを開始（1分から開始、指数バックオフで徐々に延長）
        resetBackgroundTaskInterval() // 間隔を1分にリセット
        scheduleUWBBackgroundTask() // 現在の間隔でスケジュール
        
        logger.info("📋 UWB再ペアリングスケジュール:")
        logger.info("   ⏰ 1分後: 最初のバックグラウンドタスク実行（主要タイミング）")
        logger.info("   ⏰ 2分後: 2回目のバックグラウンドタスク実行")
        logger.info("   ⏰ 4分後: 3回目のバックグラウンドタスク実行")
        logger.info("   📱 アプリがバックグラウンドの場合: 20秒ごとにハートビートでチェック")
        
        // Screen Time制限の準備
        if let screenTimeManager = screenTimeManager {
            screenTimeManager.prepareForHomeEntry()
        }
    }
    
    private func handleHomeExit() {
        logger.info("🚪 自宅エリア退出 - バックグラウンドモード移行")
        
        // デバッグ通知を送信
        if geofenceDebugNotificationEnabled {
            sendGeofenceDebugNotification(
                title: "🚪 ジオフェンス退出",
                message: "自宅エリアから離れました。Screen Time制限を無効化します。"
            )
        }
        
        // バックグラウンドアクティビティセッションを終了
        if #available(iOS 17.0, *) {
            stopBackgroundActivitySession()
        }
        
        // BGタスクのキャンセルと処理停止
        cancelUWBBackgroundTask()
        stopBackgroundHeartbeat()
        endBackgroundTask()
        
        // BGタスク間隔をリセット（次回の帰宅時に備える）
        resetBackgroundTaskInterval()
        
        // Screen Time制限を無効化
        if let screenTimeManager = screenTimeManager {
            screenTimeManager.handleHomeExit()
        }
    }
    
    @available(iOS 17.0, *)
    private func startBackgroundActivitySession() {
        backgroundActivitySession = CLBackgroundActivitySession()
        logger.info("バックグラウンドアクティビティセッション開始")
    }
    
    @available(iOS 17.0, *)
    private func stopBackgroundActivitySession() {
        if let session = backgroundActivitySession as? CLBackgroundActivitySession {
            session.invalidate()
            backgroundActivitySession = nil
            logger.info("バックグラウンドアクティビティセッション終了")
        }
    }
    
    // MARK: - ジオフェンス設定メソッド
    
    /// ジオフェンス監視を一時停止（UWB接続時に呼び出される）
    private func pauseGeofenceMonitoring() {
        guard geofencingEnabled, geofencingMonitoring else {
            logger.info("ℹ️ ジオフェンス監視は既に停止しています")
            return
        }
        
        logger.info("⏸️ ジオフェンス監視を一時停止（UWB接続により位置情報監視不要）")
        
        // 全てのジオフェンス監視を停止
        locationManager_geo.monitoredRegions.forEach { region in
            locationManager_geo.stopMonitoring(for: region)
        }
        
        DispatchQueue.main.async {
            self.geofencingMonitoring = false
        }
        
        logger.info("✅ 位置情報の「常に使用」ラベルが非表示になります")
    }
    
    /// ジオフェンス監視を再開（UWB切断時に呼び出される）
    private func resumeGeofenceMonitoring() {
        guard geofencingEnabled, !geofencingMonitoring else {
            logger.info("ℹ️ ジオフェンス監視は既に動作しています")
            return
        }
        
        guard let homeCoordinate = homeCoordinate else {
            logger.warning("⚠️ ジオフェンス再開不可: 自宅位置未設定")
            return
        }
        
        logger.info("▶️ ジオフェンス監視を再開（UWB切断により位置情報監視が必要）")
        
        // ジオフェンス監視を再開
        let homeRegion = CLCircularRegion(
            center: homeCoordinate,
            radius: homeRadius,
            identifier: "home"
        )
        homeRegion.notifyOnEntry = true
        homeRegion.notifyOnExit = true
        
        locationManager_geo.startMonitoring(for: homeRegion)
        
        DispatchQueue.main.async {
            self.geofencingMonitoring = true
        }
        
        logger.info("✅ ジオフェンス監視再開完了")
    }
    
    /// ジオフェンスデバッグ通知の有効/無効を切り替え
    func setGeofenceDebugNotification(enabled: Bool) {
        logger.info("🔔 ジオフェンスデバッグ通知: \(enabled ? "有効" : "無効")")
        
        DispatchQueue.main.async {
            self.geofenceDebugNotificationEnabled = enabled
        }
        
        // UserDefaultsに保存
        userDefaults.set(enabled, forKey: "geofenceDebugNotificationEnabled")
    }
    
    /// UWBペアリングデバッグ通知の有効/無効を切り替え
    func setUWBPairingDebugNotification(enabled: Bool) {
        logger.info("🔔 UWBペアリングデバッグ通知: \(enabled ? "有効" : "無効")")
        
        DispatchQueue.main.async {
            self.uwbPairingDebugNotificationEnabled = enabled
        }
        
        // UserDefaultsに保存
        userDefaults.set(enabled, forKey: "uwbPairingDebugNotificationEnabled")
    }
    
    /// ジオフェンスデバッグ通知を送信
    private func sendGeofenceDebugNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.badge = 0
        
        // 通知をすぐに送信
        let request = UNNotificationRequest(
            identifier: "geofence_debug_\(UUID().uuidString)",
            content: content,
            trigger: nil // すぐに送信
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("ジオフェンスデバッグ通知送信失敗: \(error)")
            } else {
                self.logger.info("ジオフェンスデバッグ通知送信成功: \(title)")
            }
        }
    }
    
    /// UWBペアリングデバッグ通知を送信
    private func sendUWBPairingDebugNotification(title: String, message: String, deviceName: String = "") {
        guard uwbPairingDebugNotificationEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = deviceName.isEmpty ? message : "[\(deviceName)] \(message)"
        content.sound = .default
        content.badge = 0
        
        // 通知をすぐに送信
        let request = UNNotificationRequest(
            identifier: "uwb_pairing_debug_\(UUID().uuidString)",
            content: content,
            trigger: nil // すぐに送信
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("UWBペアリングデバッグ通知送信失敗: \(error)")
            } else {
                self.logger.info("UWBペアリングデバッグ通知送信成功: \(title)")
            }
        }
    }
}

// 現在地取得用のヘルパークラス
class CurrentLocationGetter: NSObject, CLLocationManagerDelegate {
    private let completion: (CLLocationCoordinate2D) -> Void
    
    init(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.completion = completion
        super.init()
        print("🔧 CurrentLocationGetterが初期化されました")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("📍 didUpdateLocationsが呼び出されました。取得した位置数: \(locations.count)")
        guard let location = locations.first else { 
            print("❌ 位置情報が取得できませんでした")
            return 
        }
        print("✅ 位置情報を取得: \(location.coordinate)")
        completion(location.coordinate)
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ 位置情報取得エラー: \(error.localizedDescription)")
        manager.stopUpdatingLocation()
    }
}

#Preview {
    UWBSettingsView()
}
