import SwiftUI
import BackgroundTasks

// AppDelegate for BGTaskScheduler registration
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 AppDelegate: アプリ起動 - BGTaskScheduler登録開始")
        
        // BGTaskSchedulerへの登録は一度だけ行う
        registerBackgroundTasks()
        
        return true
    }
    
    private func registerBackgroundTasks() {
        // ScreenTimeManager用のバックグラウンドタスク
        // 注: ScreenTimeManagerはContentViewで作成されるため、
        // ここではタスクIDの登録のみを行い、実際の処理は各マネージャーで行う
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.locationreminder.app.screentime.monitoring",
            using: nil
        ) { task in
            print("📱 BGTask実行: ScreenTime監視")
            // ContentViewで作成されたScreenTimeManagerインスタンスが
            // スケジュールしたタスクがここで実行される
            // 実際の処理はタスクスケジュール時に設定されたクロージャで実行される
            task.setTaskCompleted(success: true)
        }
        
        // UWBManager用のバックグラウンドタスク
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.locationreminder.app.uwb.maintenance",
            using: nil
        ) { task in
            print("📱 BGTask実行: UWB再接続")
            // UWBManagerはシングルトンなので直接呼び出し可能
            UWBManager.shared.handleBackgroundMaintenanceTaskWrapper(task: task as! BGAppRefreshTask)
        }
        
        print("✅ BGTaskScheduler登録完了")
    }
}

@main
struct LocationReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
} 
