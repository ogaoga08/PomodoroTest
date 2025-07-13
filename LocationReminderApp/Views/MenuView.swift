import SwiftUI

struct MenuView: View {
    var body: some View {
        List {
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
}

#Preview {
    MenuView()
} 
