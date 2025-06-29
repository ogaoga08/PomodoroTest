import SwiftUI
import CoreBluetooth
import NearbyInteraction
import UserNotifications
import os

// NotificationManager クラス
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private init() {
        checkNotificationPermission()
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
    
    func setRoomStatusNotification(deviceName: String, isInBubble: Bool) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Territory"
        
        if isInBubble {
            content.subtitle = "🔥タスク開始の時間です🔥"
            content.body = "部屋に入りました！今日のタスクを始めましょう！"
        } else {
            content.subtitle = "🎐少し休憩しましょう🎐"
            content.body = "部屋の外に出ました。深呼吸しましょう。"
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
class UWBManager: NSObject, ObservableObject {
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
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        notificationManager.requestAuthorization()
    }
    
    func startScanning() {
        guard let centralManager = centralManager else { return }
        
        if centralManager.state == .poweredOn {
            logger.info("Bluetooth スキャン開始")
            centralManager.scanForPeripherals(
                withServices: [QorvoNIService.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
            scanningError = nil
        } else {
            scanningError = "Bluetoothが利用できません"
            logger.error("Bluetoothが利用できない状態: \(centralManager.state.rawValue)")
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        logger.info("スキャン停止")
    }
    
    func connectToDevice(_ device: UWBDevice) {
        guard let centralManager = centralManager else { return }
        
        logger.info("デバイスへ接続開始: \(device.name)")
        isConnecting = true
        device.status = .connected
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnectFromDevice(_ device: UWBDevice) {
        guard let centralManager = centralManager else { return }
        
        logger.info("デバイスから切断: \(device.name)")
        centralManager.cancelPeripheralConnection(device.peripheral)
        
        // NISessionを無効化
        if let session = niSessions[device.uniqueID] {
            session.invalidate()
            niSessions.removeValue(forKey: device.uniqueID)
        }
        accessoryConfigurations.removeValue(forKey: device.uniqueID)
        
        DispatchQueue.main.async {
            device.status = DeviceStatus.discovered
            device.distance = nil
        }
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
        logger.info("Nearby Interaction許可を要求")
        
        // デバイスがUWBをサポートしているかチェック
        if #available(iOS 16.0, *) {
            guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
                DispatchQueue.main.async {
                    self.niPermissionError = "このデバイスはUWB（Nearby Interaction）をサポートしていません"
                    self.niPermissionStatus = "非対応"
                }
                logger.error("デバイスがUWBをサポートしていません")
                return
            }
        }
        
        // 許可を求めるためのテストセッションを作成
        permissionTestSession = NISession()
        permissionTestSession?.delegate = self
        
        DispatchQueue.main.async {
            self.niPermissionStatus = "確認中..."
            self.niPermissionError = nil
        }
        
        // セッションの作成だけで基本的な権限チェックを行う
        // 実際のrun()は実デバイス接続時に行う
        logger.info("NISession作成完了: 基本機能確認")
        
        // 短時間後に状態を更新（セッション作成が成功した場合）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.permissionTestSession != nil {
                self.niPermissionStatus = "利用可能"
                self.logger.info("Nearby Interaction基本機能利用可能")
                
                // テストセッションをクリーンアップ
                self.permissionTestSession?.invalidate()
                self.permissionTestSession = nil
            }
        }
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
        logger.info("アクセサリ設定データを受信: \(device.name)")
        
        do {
            // iOS 15対応: データから直接設定を作成
            let configuration = try NINearbyAccessoryConfiguration(
                accessoryData: configData,
                bluetoothPeerIdentifier: device.peripheral.identifier
            )
            
            accessoryConfigurations[device.uniqueID] = configuration
            
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
            
            logger.info("NISession開始: \(device.name) - 許可ダイアログ表示")
            
        } catch {
            logger.error("設定データの解析に失敗: \(error)")
            handleNIError(error)
        }
    }
    
    private func handleUWBDidStart(device: UWBDevice) {
        DispatchQueue.main.async {
            device.status = DeviceStatus.ranging
        }
        updateConnectionStatus()
        logger.info("UWB測定開始: \(device.name)")
    }
    
    private func handleUWBDidStop(device: UWBDevice) {
        DispatchQueue.main.async {
            device.status = DeviceStatus.connected
            device.distance = nil
        }
        updateConnectionStatus()
        logger.info("UWB測定停止: \(device.name)")
    }
    
    private func handleAccessoryPaired(device: UWBDevice) {
        DispatchQueue.main.async {
            device.status = DeviceStatus.paired
        }
        updateConnectionStatus()
        
        // デバイス情報を保存
        saveDeviceInfo(device)
        
        // 初期化メッセージを送信
        let initMessage = Data([MessageId.initialize.rawValue])
        sendDataToDevice(initMessage, device: device)
        
        logger.info("アクセサリペアリング完了: \(device.name)")
    }
    
    private func handleiOSNotify(data: Data, device: UWBDevice) {
        guard notificationsEnabled else { return }
        
        // データの最初の3バイトをスキップして、メッセージを取得
        if data.count > 3, let message = String(bytes: data.advanced(by: 3), encoding: .utf8) {
            // デバイスからのメッセージを直接解釈して、bubbleの状態を判断する
            // これにより、アプリ内の状態更新とのタイムラグの問題を解消する
            let isInBubbleBasedOnMessage = message.contains("in")
            
            notificationManager.setRoomStatusNotification(deviceName: device.name, isInBubble: isInBubbleBasedOnMessage)
            logger.info("iOSNotify受信: \(device.name) - \(message)")
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
        
        // 状態が変化した場合のみ通知
        if previousSecureBubbleStatus != isCurrentlyInBubble {
            DispatchQueue.main.async {
                self.isInSecureBubble = isCurrentlyInBubble
            }
            
            previousSecureBubbleStatus = isCurrentlyInBubble
            
            logger.info("Secure Bubble状態変化: \(device.name) - \(isCurrentlyInBubble ? "内部" : "外部") - 距離: \(distance)m")
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
                
                // 自動接続開始
                if peripheral.state != .connected {
                    logger.info("自動接続試行: \(savedDevice.name)")
                    centralManager.connect(peripheral, options: nil)
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
        
        switch niError.code {
        case -5884: // NIERROR_USER_DID_NOT_ALLOW
            if isPermissionTest {
                DispatchQueue.main.async {
                    self.niPermissionError = "Nearby Interaction（UWB）の許可が拒否されました。設定アプリから許可してください。"
                    self.niPermissionStatus = "拒否"
                }
                logger.error("ユーザーがNearby Interactionを拒否しました")
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
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可済み"
            self.niPermissionError = nil
        }
        logger.info("Nearby Interaction許可が承認されました")
        
        // 許可テスト用セッションをクリーンアップ
        permissionTestSession?.invalidate()
        permissionTestSession = nil
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
            // 自動接続を開始
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startAutoReconnection()
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
            centralManager?.connect(peripheral, options: nil)
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
        
        DispatchQueue.main.async {
            self.isConnecting = false
        }
        
        if let device = findDevice(peripheral: peripheral) {
            DispatchQueue.main.async {
                device.status = DeviceStatus.discovered
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("デバイス切断: \(peripheral.name ?? "Unknown")")
        
        if let device = findDevice(peripheral: peripheral) {
            DispatchQueue.main.async {
                device.status = DeviceStatus.discovered
                device.distance = nil
            }
            updateConnectionStatus()
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
            logger.error("データ受信エラー: \(error)")
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
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
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
        
        guard let device = targetDevice else { return }
        
        // 設定データを送信
        var message = Data([MessageId.configureAndStart.rawValue])
        message.append(shareableConfigurationData)
        sendDataToDevice(message, device: device)
        
        logger.info("共有設定データ送信: \(device.name) - NI許可済み")
    }
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            handleNIPermissionGranted()
            return
        }
        
        // 実際のデバイスセッションで距離更新があった場合も許可済みを示す
        DispatchQueue.main.async {
            self.niPermissionStatus = "許可済み"
            self.niPermissionError = nil
        }
        
        guard let accessory = nearbyObjects.first,
              let distance = accessory.distance else { return }
        
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
            device.distance = distance
            device.status = DeviceStatus.ranging
        }
        updateConnectionStatus()
        
        // Secure bubble判定を実行
        checkSecureBubbleStatus(distance: distance, device: device)
        
        logger.info("距離更新: \(device.name) - \(distance)m")
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
        logger.error("NISession無効化: \(error)")
        
        // エラーハンドリング
        handleNIError(error)
        
        // 許可テスト用セッションの場合
        if session == permissionTestSession {
            permissionTestSession = nil
            return
        }
        
        // セッションに対応するデバイスを見つけて削除
        for (deviceID, niSession) in niSessions {
            if niSession == session {
                niSessions.removeValue(forKey: deviceID)
                accessoryConfigurations.removeValue(forKey: deviceID)
                
                // デバイス状態をリセット
                if let device = findDevice(uniqueID: deviceID) {
                    DispatchQueue.main.async {
                        device.distance = nil
                        if device.status == DeviceStatus.ranging {
                            device.status = DeviceStatus.connected
                        }
                    }
                    updateConnectionStatus()
                }
                break
            }
        }
    }
}

struct UWBSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var uwbManager = UWBManager.shared
    @State private var showingNIPermissionAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // ヘッダー
                VStack(spacing: 16) {
                    Image(systemName: "wave.3.right.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("UWBデバイス設定")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("DWM3001CDKデバイスとの通信とリアルタイム距離測定")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // UWB許可状態表示
                HStack {
                    Image(systemName: "wave.3.right")
                        .foregroundColor(niPermissionColor)
                    Text("UWB機能: \(uwbManager.niPermissionStatus)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    if uwbManager.niPermissionStatus == "未確認" {
                        Button("機能確認") {
                            uwbManager.requestNearbyInteractionPermission()
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal)
                
                // Secure Bubble状態表示
                if uwbManager.isUWBActive {
                    HStack {
                        Image(systemName: uwbManager.isInSecureBubble ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
                        Text("Secure Bubble: \(uwbManager.isInSecureBubble ? "内部" : "外部")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
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
                        Text("発見されたデバイス")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(uwbManager.discoveredDevices) { device in
                                    DeviceRowView(device: device, uwbManager: uwbManager)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("UWB設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var niPermissionColor: Color {
        switch uwbManager.niPermissionStatus {
        case "許可済み":
            return .green
        case "拒否", "エラー", "非対応":
            return .red
        case "許可要求中...":
            return .orange
        default:
            return .gray
        }
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
                    Text("接続済み")
                        .font(.caption)
                        .foregroundColor(.gray)
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

#Preview {
    UWBSettingsView()
}
