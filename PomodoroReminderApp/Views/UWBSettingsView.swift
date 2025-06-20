import SwiftUI

struct UWBSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "wave.3.right.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("UWBモジュール設定")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("この機能は現在開発中です。\nNearby Interaction APIを使用したUWBモジュールとの通信機能を実装予定です。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("近距離デバイス検出")
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("自動ペアリング")
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("リアルタイム距離測定")
                        Spacer()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    // UWBスキャン開始の実装（将来）
                }) {
                    Text("デバイスをスキャン")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(true)
                .padding(.horizontal)
                .padding(.bottom, 30)
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
}

#Preview {
    UWBSettingsView()
} 