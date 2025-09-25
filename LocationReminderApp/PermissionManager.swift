import Foundation
import SwiftUI
import UserNotifications
import EventKit
import FamilyControls
import NearbyInteraction
import CoreBluetooth
import CoreLocation

// 許可の種類を定義
enum PermissionType: String, CaseIterable {
    case reminders = "reminders"
    case notifications = "notifications"
    case screenTime = "screenTime"
    case nearbyInteraction = "nearbyInteraction"
    case bluetooth = "bluetooth"
    case location = "location"
    
    var displayName: String {
        switch self {
        case .reminders:
            return "リマインダー"
        case .notifications:
            return "通知"
        case .screenTime:
            return "スクリーンタイム"
        case .nearbyInteraction:
            return "Nearby Interaction"
        case .bluetooth:
            return "Bluetooth"
        case .location:
            return "位置情報"
        }
    }
    
    var description: String {
        switch self {
        case .reminders:
            return "タスクの管理とリマインダー機能のために必要です"
        case .notifications:
            return "重要な通知をお送りするために必要です"
        case .screenTime:
            return "アプリの使用制限機能のために必要です"
        case .nearbyInteraction:
            return "UWBデバイスとの精密な距離測定のために必要です"
        case .bluetooth:
            return "UWBデバイスとの通信のために必要です"
        case .location:
            return "位置ベースのリマインダー機能のために必要です"
        }
    }
    
    var iconName: String {
        switch self {
        case .reminders:
            return "checklist"
        case .notifications:
            return "bell.fill"
        case .screenTime:
            return "hourglass"
        case .nearbyInteraction:
            return "wave.3.right"
        case .bluetooth:
            return "bluetooth"
        case .location:
            return "location.fill"
        }
    }
}

// 許可の状態
enum PermissionStatus {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable
    
    var displayText: String {
        switch self {
        case .notDetermined:
            return "未設定"
        case .granted:
            return "許可済み"
        case .denied:
            return "拒否"
        case .restricted:
            return "制限中"
        case .unavailable:
            return "利用不可"
        }
    }
    
    var color: Color {
        switch self {
        case .granted:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        case .unavailable:
            return .gray
        }
    }
}

// 許可管理クラス
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var permissionStatuses: [PermissionType: PermissionStatus] = [:]
    @Published var isRequestingPermissions = false
    @Published var currentRequestingPermission: PermissionType?
    @Published var showPermissionOnboarding = false
    
    // 各マネージャーへの参照
    weak var taskManager: TaskManager?
    weak var screenTimeManager: ScreenTimeManager?
    weak var uwbManager: UWBManager?
    weak var notificationManager: NotificationManager?
    
    private let locationManager = CLLocationManager()
    
    private init() {
        checkAllPermissionStatuses()
    }
    
    // 全ての許可状態をチェック
    func checkAllPermissionStatuses() {
        Task {
            await checkRemindersPermission()
            await checkNotificationsPermission()
            await checkScreenTimePermission()
            await checkNearbyInteractionPermission()
            await checkBluetoothPermission()
            await checkLocationPermission()
        }
    }
    
    // 段階的に許可を要求
    func requestPermissionsSequentially() {
        guard !isRequestingPermissions else { return }
        
        isRequestingPermissions = true
        showPermissionOnboarding = true
        
        Task {
            // 1. リマインダー許可
            if permissionStatuses[.reminders] == .notDetermined {
                currentRequestingPermission = .reminders
                await requestRemindersPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
            }
            
            // 2. 通知許可
            if permissionStatuses[.notifications] == .notDetermined {
                currentRequestingPermission = .notifications
                await requestNotificationsPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // 3. 位置情報許可
            if permissionStatuses[.location] == .notDetermined {
                currentRequestingPermission = .location
                await requestLocationPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // 4. Bluetooth許可（間接的）
            if permissionStatuses[.bluetooth] == .notDetermined {
                currentRequestingPermission = .bluetooth
                await requestBluetoothPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // 5. Nearby Interaction許可
            if permissionStatuses[.nearbyInteraction] == .notDetermined {
                currentRequestingPermission = .nearbyInteraction
                await requestNearbyInteractionPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // 6. スクリーンタイム許可（最後）
            if permissionStatuses[.screenTime] == .notDetermined {
                currentRequestingPermission = .screenTime
                await requestScreenTimePermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            currentRequestingPermission = nil
            isRequestingPermissions = false
            showPermissionOnboarding = false
            
            // 最終状態をチェック
            checkAllPermissionStatuses()
        }
    }
    
    // 個別の許可要求メソッド
    private func requestRemindersPermission() async {
        guard let taskManager = taskManager else { return }
        taskManager.requestReminderAccess()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await checkRemindersPermission()
    }
    
    private func requestNotificationsPermission() async {
        guard let notificationManager = notificationManager else { return }
        notificationManager.requestAuthorization()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await checkNotificationsPermission()
    }
    
    private func requestLocationPermission() async {
        locationManager.requestWhenInUseAuthorization()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await checkLocationPermission()
    }
    
    private func requestBluetoothPermission() async {
        // Bluetoothの許可は実際のスキャン開始時に自動的に要求される
        guard let uwbManager = uwbManager else { return }
        uwbManager.startScanning()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await checkBluetoothPermission()
    }
    
    private func requestNearbyInteractionPermission() async {
        guard let uwbManager = uwbManager else { return }
        
        // UWBManagerのNearby Interaction許可要求を呼び出し
        uwbManager.requestNearbyInteractionPermission()
        
        // 許可ダイアログの表示と応答を待つ（より長い時間待機）
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5秒待機
        
        // 状態を再チェック
        await checkNearbyInteractionPermission()
    }
    
    private func requestScreenTimePermission() async {
        guard let screenTimeManager = screenTimeManager else { return }
        screenTimeManager.requestAuthorization()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await checkScreenTimePermission()
    }
    
    // 個別の許可状態チェックメソッド
    private func checkRemindersPermission() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let permissionStatus: PermissionStatus
        
        switch status {
        case .notDetermined:
            permissionStatus = .notDetermined
        case .authorized, .fullAccess:
            permissionStatus = .granted
        case .denied:
            permissionStatus = .denied
        case .restricted:
            permissionStatus = .restricted
        case .writeOnly:
            permissionStatus = .granted
        @unknown default:
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.reminders] = permissionStatus
    }
    
    private func checkNotificationsPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let permissionStatus: PermissionStatus
        
        switch settings.authorizationStatus {
        case .notDetermined:
            permissionStatus = .notDetermined
        case .authorized, .provisional, .ephemeral:
            permissionStatus = .granted
        case .denied:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.notifications] = permissionStatus
    }
    
    private func checkScreenTimePermission() async {
        let status = AuthorizationCenter.shared.authorizationStatus
        let permissionStatus: PermissionStatus
        
        switch status {
        case .notDetermined:
            permissionStatus = .notDetermined
        case .approved:
            permissionStatus = .granted
        case .denied:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.screenTime] = permissionStatus
    }
    
    private func checkNearbyInteractionPermission() async {
        // iOS 16.0以降でNearby Interactionをサポートしているかチェック
        if #available(iOS 16.0, *) {
            // デバイスがUWBをサポートしているかチェック
            guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
                permissionStatuses[.nearbyInteraction] = .unavailable
                return
            }
        } else {
            permissionStatuses[.nearbyInteraction] = .unavailable
            return
        }
        
        // UWBManagerの状態を参照
        guard let uwbManager = uwbManager else {
            permissionStatuses[.nearbyInteraction] = .notDetermined
            return
        }
        
        let permissionStatus: PermissionStatus
        switch uwbManager.niPermissionStatus {
        case "許可済み":
            // 実際に許可ダイアログを通過した場合のみ許可済みとする
            permissionStatus = .granted
        case "拒否":
            permissionStatus = .denied
        case "未確認", "", "許可要求中...":
            permissionStatus = .notDetermined
        case "非対応":
            permissionStatus = .unavailable
        case "エラー", "タイムアウト", "制限超過", "設定不備":
            permissionStatus = .denied
        default:
            // 初期状態や不明な状態の場合は必ず未確認とする
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.nearbyInteraction] = permissionStatus
    }
    
    private func checkBluetoothPermission() async {
        // Bluetoothの許可状態はCBCentralManagerの状態から推測
        guard let uwbManager = uwbManager else {
            permissionStatuses[.bluetooth] = .unavailable
            return
        }
        
        let permissionStatus: PermissionStatus
        if uwbManager.isScanning || !uwbManager.discoveredDevices.isEmpty {
            permissionStatus = .granted
        } else {
            // より詳細な状態チェックが必要な場合はCBCentralManagerの状態を確認
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.bluetooth] = permissionStatus
    }
    
    private func checkLocationPermission() async {
        let status = locationManager.authorizationStatus
        let permissionStatus: PermissionStatus
        
        switch status {
        case .notDetermined:
            permissionStatus = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            permissionStatus = .granted
        case .denied:
            permissionStatus = .denied
        case .restricted:
            permissionStatus = .restricted
        @unknown default:
            permissionStatus = .notDetermined
        }
        
        permissionStatuses[.location] = permissionStatus
    }
    
    // 特定の許可を個別に要求
    func requestPermission(_ type: PermissionType) {
        Task {
            currentRequestingPermission = type
            
            switch type {
            case .reminders:
                await requestRemindersPermission()
            case .notifications:
                await requestNotificationsPermission()
            case .screenTime:
                await requestScreenTimePermission()
            case .nearbyInteraction:
                await requestNearbyInteractionPermission()
            case .bluetooth:
                await requestBluetoothPermission()
            case .location:
                await requestLocationPermission()
            }
            
            currentRequestingPermission = nil
        }
    }
    
    // 全ての必要な許可が得られているかチェック
    var allRequiredPermissionsGranted: Bool {
        let requiredPermissions: [PermissionType] = [.reminders, .notifications]
        return requiredPermissions.allSatisfy { 
            permissionStatuses[$0] == .granted 
        }
    }
    
    // 設定アプリを開く
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}
