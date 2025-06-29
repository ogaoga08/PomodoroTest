import SwiftUI

struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingUWBSettings = false
    @State private var showingRoomSettings = false
    @State private var showingOnboarding = false
    @State private var showingScreenTimeSettings = false
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    showingUWBSettings = true
                }) {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("UWBモジュール設定")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    showingScreenTimeSettings = true
                }) {
                    HStack {
                        Image(systemName: "hourglass")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text("Screen Time設定")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    showingOnboarding = true
                }) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("使い方")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingUWBSettings) {
            UWBSettingsView()
        }
        .sheet(isPresented: $showingScreenTimeSettings) {
            ScreenTimeSettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
    }
}

#Preview {
    MenuView()
} 
