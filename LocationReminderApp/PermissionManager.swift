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
class PermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
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
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    
    private override init() {
        super.init()
        // 初期化時は状態チェックしない（オンボーディングで処理）
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // CLLocationManagerDelegate
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                print("📍 位置情報更新: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                locationContinuation?.resume(returning: location)
                locationContinuation = nil
                locationManager.stopUpdatingLocation()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ 位置情報取得エラー: \(error.localizedDescription)")
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
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
            
            // 5. スクリーンタイム許可（最後）
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
        guard let taskManager = taskManager else {
            print("❌ PermissionManager: taskManagerが設定されていません")
            return
        }
        
        print("📝 PermissionManager: リマインダー許可をリクエスト")
        
        // 現在の状態を取得
        let initialStatus = permissionStatuses[.reminders]
        print("📝 初期状態: \(initialStatus)")
        
        // 許可をリクエスト
        taskManager.requestReminderAccess()
        
        // ダイアログが表示されるまで少し待機
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // ダイアログが表示されて応答されるまで待機（最大20秒）
        for i in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkRemindersPermission()
            
            let currentStatus = permissionStatuses[.reminders]
            if i % 4 == 0 { // 2秒ごとにログ出力
                print("📝 リマインダー状態チェック (\(i/2)秒): \(currentStatus)")
            }
            
            // 状態が変化したら完了
            if currentStatus != initialStatus && currentStatus != .notDetermined {
                print("✅ リマインダー許可完了: \(currentStatus)")
                break
            }
        }
        
        // 最終状態を確認
        await checkRemindersPermission()
        print("📝 リマインダー最終状態: \(permissionStatuses[.reminders] ?? .notDetermined)")
    }
    
    private func requestNotificationsPermission() async {
        guard let notificationManager = notificationManager else {
            print("❌ PermissionManager: notificationManagerが設定されていません")
            return
        }
        
        print("🔔 PermissionManager: 通知許可をリクエスト")
        
        // 現在の状態を取得
        let initialStatus = permissionStatuses[.notifications]
        print("🔔 初期状態: \(initialStatus)")
        
        // 許可をリクエスト
        notificationManager.requestAuthorization()
        
        // ダイアログが表示されるまで少し待機
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // ダイアログが表示されて応答されるまで待機（最大20秒）
        for i in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkNotificationsPermission()
            
            let currentStatus = permissionStatuses[.notifications]
            if i % 4 == 0 { // 2秒ごとにログ出力
                print("🔔 通知状態チェック (\(i/2)秒): \(currentStatus)")
            }
            
            // 状態が変化したら完了
            if currentStatus != initialStatus && currentStatus != .notDetermined {
                print("✅ 通知許可完了: \(currentStatus)")
                break
            }
        }
        
        // 最終状態を確認
        await checkNotificationsPermission()
        print("🔔 通知最終状態: \(permissionStatuses[.notifications] ?? .notDetermined)")
    }
    
    private func requestLocationPermission() async {
        print("📍 PermissionManager: 位置情報許可をリクエスト")
        
        // 現在の状態を取得
        let initialStatus = permissionStatuses[.location]
        print("📍 初期状態: \(initialStatus)")
        
        // まず「使用中の許可」を要求
        locationManager.requestWhenInUseAuthorization()
        
        // ダイアログが表示されるまで少し待機
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // ダイアログが表示されて応答されるまで待機（最大20秒）
        for i in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkLocationPermission()
            
            let currentStatus = permissionStatuses[.location]
            if i % 4 == 0 { // 2秒ごとにログ出力
                print("📍 位置情報状態チェック (\(i/2)秒): \(currentStatus)")
            }
            
            // 状態が変化したら次へ
            if currentStatus != initialStatus && currentStatus != .notDetermined {
                print("✅ 使用中の許可完了: \(currentStatus)")
                break
            }
        }
        
        // 少し待機してから「常に許可」を要求
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        print("📍 「常に許可」をリクエスト")
        // 「常に許可」を要求
        locationManager.requestAlwaysAuthorization()
        
        // 再度ダイアログが表示されて応答されるまで待機（最大20秒）
        for i in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkLocationPermission()
            
            let currentStatus = permissionStatuses[.location]
            if i % 4 == 0 { // 2秒ごとにログ出力
                print("📍 常に許可状態チェック (\(i/2)秒): \(currentStatus)")
            }
        }
        
        // 最終状態を確認
        await checkLocationPermission()
        let finalStatus = permissionStatuses[.location]
        print("📍 位置情報最終状態: \(finalStatus)")
        
        // 位置情報許可が得られた場合、現在地をジオフェンス住所として自動登録
        if finalStatus == .granted {
            await setupGeofenceWithCurrentLocation()
        }
    }
    
    // 現在地をジオフェンス住所として自動登録
    private func setupGeofenceWithCurrentLocation() async {
        print("🏠 現在地をジオフェンス住所として自動登録します")
        
        guard let uwbManager = uwbManager else {
            print("❌ uwbManagerが設定されていません")
            return
        }
        
        // 現在地を取得
        let currentLocation = await getCurrentLocation()
        
        if let location = currentLocation {
            print("🏠 現在地取得成功: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            
            // UWBManagerに現在地を自宅として設定
            uwbManager.setHomeLocation(location.coordinate)
            uwbManager.geofencingEnabled = true
            print("✅ ジオフェンス設定完了")
        } else {
            print("⚠️ 現在地の取得に失敗しました")
        }
    }
    
    // 現在地を取得（async/await）
    private func getCurrentLocation() async -> CLLocation? {
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            
            // 位置情報の更新を開始
            locationManager.startUpdatingLocation()
            
            // タイムアウト処理（10秒）
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    print("⚠️ 位置情報取得タイムアウト")
                    self.locationContinuation?.resume(returning: nil)
                    self.locationContinuation = nil
                    self.locationManager.stopUpdatingLocation()
                }
            }
        }
    }
    
    private func requestBluetoothPermission() async {
        // Bluetoothの許可は実際のスキャン開始時に自動的に要求される
        guard let uwbManager = uwbManager else {
            print("❌ PermissionManager: uwbManagerが設定されていません")
            return
        }
        
        print("📡 PermissionManager: Bluetooth許可をリクエスト")
        
        // 現在の状態を取得
        let initialStatus = permissionStatuses[.bluetooth]
        print("📡 初期状態: \(initialStatus)")
        
        // Bluetooth delegateを有効化（まだ有効化されていない場合）
        uwbManager.enableBluetoothDelegate()
        
        // delegateが設定されるまで少し待機
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        // スキャンを開始してダイアログを表示
        uwbManager.startScanning()
        
        // ダイアログが表示されるまで少し待機
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // ダイアログが表示されて応答されるまで待機（最大20秒）
        for i in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkBluetoothPermission()
            
            let currentStatus = permissionStatuses[.bluetooth]
            if i % 4 == 0 { // 2秒ごとにログ出力
                print("📡 Bluetooth状態チェック (\(i/2)秒): \(currentStatus)")
            }
            
            // 状態が変化したら完了
            if currentStatus != initialStatus && currentStatus != .notDetermined {
                print("✅ Bluetooth許可完了: \(currentStatus)")
                break
            }
        }
        
        // 最終状態を確認
        await checkBluetoothPermission()
        let finalStatus = permissionStatuses[.bluetooth]
        print("📡 Bluetooth最終状態: \(finalStatus)")
        
        // Bluetooth許可が得られた場合、UWBデバイスの自動セットアップを開始
        if finalStatus == .granted {
            await setupUWBDeviceAutomatically()
        }
    }
    
    // UWBデバイスの自動セットアップ（検出→接続→ペアリング→NIセッション開始）
    private func setupUWBDeviceAutomatically() async {
        print("🔵 UWBデバイスの自動セットアップを開始します")
        
        guard let uwbManager = uwbManager else {
            print("❌ uwbManagerが設定されていません")
            return
        }
        
        // 既にスキャン中の場合はそのまま継続、そうでなければ開始
        if !uwbManager.isScanning {
            print("📡 UWBデバイスのスキャンを開始")
            uwbManager.startScanning()
        } else {
            print("📡 既にスキャン中です")
        }
        
        // デバイスが見つかるまで待機（最大30秒）
        print("⏳ UWBデバイスの検出を待機中...")
        for i in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 発見されたデバイスをチェック
            if !uwbManager.discoveredDevices.isEmpty {
                let device = uwbManager.discoveredDevices[0]
                print("✅ UWBデバイスを発見: \(device.name)")
                
                // デバイスに自動接続
                print("🔌 デバイスに自動接続中...")
                await MainActor.run {
                    uwbManager.connectToDevice(device)
                }
                
                // 接続とペアリングの完了を待機（最大60秒）
                print("⏳ 接続とペアリングの完了を待機中...")
                for j in 0..<120 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                    
                    if j % 4 == 0 { // 2秒ごとにステータス確認
                        print("📊 デバイスステータス: \(device.status.rawValue)")
                    }
                    
                    // ranging状態（NIセッション開始済み）になったら完了
                    if device.status == .ranging {
                        print("✅ UWBデバイスのセットアップ完了！")
                        print("   - 距離測定中: \(device.distance != nil ? String(format: "%.2fm", device.distance!) : "測定中...")")
                        
                        // スキャンを停止
                        await MainActor.run {
                            uwbManager.stopScanning()
                        }
                        return
                    }
                }
                
                print("⚠️ UWBセットアップがタイムアウトしました")
                return
            }
            
            // 10秒ごとに進捗をログ
            if i % 20 == 0 && i > 0 {
                print("⏳ デバイス検出待機中... (\(i/2)秒経過)")
            }
        }
        
        print("⚠️ UWBデバイスが見つかりませんでした（30秒間）")
        print("💡 手動でUWB設定画面からデバイスをスキャンしてください")
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
        
        // 現在の状態を取得
        let initialStatus = permissionStatuses[.screenTime]
        
        // 許可をリクエスト
        screenTimeManager.requestAuthorization()
        
        // ダイアログが表示されて応答されるまで待機（最大10秒）
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            await checkScreenTimePermission()
            
            // 状態が変化したら完了
            if permissionStatuses[.screenTime] != initialStatus && permissionStatuses[.screenTime] != .notDetermined {
                break
            }
        }
        
        // 最終状態を確認
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
        // Bluetoothの許可状態はCBCentralManagerの状態から確認
        guard let uwbManager = uwbManager else {
            permissionStatuses[.bluetooth] = .unavailable
            return
        }
        
        let permissionStatus: PermissionStatus
        
        switch uwbManager.bluetoothState {
        case .poweredOn:
            // Bluetoothが有効な場合は許可済み
            permissionStatus = .granted
        case .unauthorized:
            // Bluetoothの許可が拒否された場合
            permissionStatus = .denied
        case .poweredOff:
            // Bluetoothが無効（許可は得ているが電源オフ）
            permissionStatus = .granted
        case .unsupported:
            // デバイスがBluetoothをサポートしていない
            permissionStatus = .unavailable
        case .unknown, .resetting:
            // 状態が不明または初期化中
            permissionStatus = .notDetermined
        @unknown default:
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
        print("🚀 requestPermission呼び出し: \(type.displayName)")
        
        Task {
            currentRequestingPermission = type
            print("📌 currentRequestingPermissionを設定: \(type.displayName)")
            
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
            
            print("🏁 \(type.displayName)のリクエスト処理完了、currentRequestingPermissionをnilに設定")
            currentRequestingPermission = nil
        }
    }
    
    // 全ての必要な許可が得られているかチェック
    var allRequiredPermissionsGranted: Bool {
        let requiredPermissions: [PermissionType] = [.reminders, .notifications, .bluetooth, .screenTime, .location]
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
