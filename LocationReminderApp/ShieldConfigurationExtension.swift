import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

// ShieldConfigurationExtension
// この拡張機能は、ブロックされたアプリが起動されようとしたときに表示される画面をカスタマイズします
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // アプリケーションがブロックされたときの設定
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: ShieldConfiguration.Label(
                text: "アプリがブロックされています",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "現在、Secure Bubble内のため、このアプリの使用が制限されています。",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Secure Bubbleから出る",
                color: .systemBlue
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "設定を変更",
                color: .systemGray
            )
        )
    }
    
    override func configuration(shielding applicationCategory: ApplicationCategory) -> ShieldConfiguration {
        // アプリカテゴリがブロックされたときの設定
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "apps.iphone.landscape"),
            title: ShieldConfiguration.Label(
                text: "アプリカテゴリがブロックされています",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "現在、Secure Bubble内のため、このカテゴリのアプリの使用が制限されています。",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Secure Bubbleから出る",
                color: .systemBlue
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "設定を変更",
                color: .systemGray
            )
        )
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        // Webドメインがブロックされたときの設定
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "globe.badge.chevron.backward"),
            title: ShieldConfiguration.Label(
                text: "Webサイトがブロックされています",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "現在、Secure Bubble内のため、このWebサイトの閲覧が制限されています。",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Secure Bubbleから出る",
                color: .systemBlue
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "設定を変更",
                color: .systemGray
            )
        )
    }
    
    override func configuration(shielding webCategory: WebCategory) -> ShieldConfiguration {
        // Webカテゴリがブロックされたときの設定
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "globe.badge.chevron.backward"),
            title: ShieldConfiguration.Label(
                text: "Webカテゴリがブロックされています",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "現在、Secure Bubble内のため、このカテゴリのWebサイトの閲覧が制限されています。",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Secure Bubbleから出る",
                color: .systemBlue
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "設定を変更",
                color: .systemGray
            )
        )
    }
}

// ShieldActionExtension
// この拡張機能は、ブロック画面でユーザーがボタンを押したときの動作を処理します
class ShieldActionExtension: ShieldActionDelegate {
    
    override func handle(action: ShieldAction, for application: Application, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // プライマリボタンが押された場合の処理
            // 実際には、この処理ではSecure Bubbleから出ることはできません
            // ユーザーに物理的に移動してもらう必要があります
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            // セカンダリボタンが押された場合の処理
            // 設定アプリを開く
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                // 注意: Extension内ではUIApplicationを直接使用できません
                // 代わりに、メインアプリに通知を送信する必要があります
                sendNotificationToMainApp(action: "openSettings")
            }
            completionHandler(.defer)
            
        @unknown default:
            completionHandler(.defer)
        }
    }
    
    override func handle(action: ShieldAction, for applicationCategory: ApplicationCategory, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            sendNotificationToMainApp(action: "openSettings")
            completionHandler(.defer)
            
        @unknown default:
            completionHandler(.defer)
        }
    }
    
    override func handle(action: ShieldAction, for webDomain: WebDomain, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            sendNotificationToMainApp(action: "openSettings")
            completionHandler(.defer)
            
        @unknown default:
            completionHandler(.defer)
        }
    }
    
    override func handle(action: ShieldAction, for webCategory: WebCategory, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            sendNotificationToMainApp(action: "openSettings")
            completionHandler(.defer)
            
        @unknown default:
            completionHandler(.defer)
        }
    }
    
    // メインアプリに通知を送信するヘルパー関数
    private func sendNotificationToMainApp(action: String) {
        // App Groupsを使用してメインアプリと通信
        let defaults = UserDefaults(suiteName: "group.com.locationreminder.shieldaction")
        defaults?.set(action, forKey: "pendingAction")
        defaults?.set(Date(), forKey: "actionTimestamp")
        
        // メインアプリはポーリングで確認するため、ここでは通知は不要
        print("Shield action sent to main app: \(action)")
    }
} 