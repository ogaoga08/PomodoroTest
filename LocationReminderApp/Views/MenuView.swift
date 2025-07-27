import SwiftUI

struct MenuView: View {
    @ObservedObject var taskManager: TaskManager
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: StatisticsView(taskManager: taskManager)) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text("統計・分析")
                            .foregroundColor(.primary)
                    }
                }
                
                NavigationLink(destination: UWBSettingsView()) {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("UWBモジュール設定")
                            .foregroundColor(.primary)
                    }
                }
                
                NavigationLink(destination: ScreenTimeSettingsView()) {
                    HStack {
                        Image(systemName: "hourglass")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text("Screen Time設定")
                            .foregroundColor(.primary)
                    }
                }
                
                NavigationLink(destination: OnboardingView()) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("本アプリとは")
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    MenuView(taskManager: TaskManager())
} 
