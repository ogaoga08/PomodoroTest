import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    private let pages = [
        "本アプリは先延ばし防止のための位置情報活用リマインダーアプリです。",
        "先延ばしは、身体的・精神的負担に影響を与えるが、ついついやってしまう行為だとされています。",
        "本アプリはそんな先延ばし癖を解消するために作られました。",
        "先延ばしを防ぐ最も有効的な手段は、\"すぐやる\"ことです。",
        "自室に入ったら\"すぐやる\"。この行動を習慣化することで、あなたの人生を豊かにすることでしょう。",
        "さあ、始めましょう"
    ]
    
    private let icons = [
        "location.circle.fill",
        "brain.head.profile",
        "star.circle.fill",
        "bolt.circle.fill",
        "house.circle.fill",
        "play.circle.fill"
    ]
    
    private let colors: [Color] = [
        .blue,
        .orange,
        .purple,
        .green,
        .red,
        .pink
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // カルーセルコンテンツ
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    VStack(spacing: 40) {
                        Spacer()
                        
                        // アイコン
                        Image(systemName: icons[index])
                            .font(.system(size: 80))
                            .foregroundColor(colors[index])
                            .scaleEffect(1.2)
                        
                        // テキスト
                        Text(pages[index])
                            .font(.title2)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .padding(.horizontal, 40)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            
            // ページインジケーター
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? colors[currentPage] : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentPage ? 1.2 : 1.0)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.bottom, 30)
            
            // ボタン
            VStack(spacing: 16) {
                if currentPage < pages.count - 1 {
                    // Nextボタン
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }) {
                        HStack {
                            Text("次へ")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colors[currentPage])
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 40)
                    
                    // スキップボタン
                    Button("スキップ") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    
                } else {
                    // スタートボタン（最後のページ）
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("始める")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [colors[currentPage], colors[currentPage].opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: colors[currentPage].opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 40)
                    .scaleEffect(1.05)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 50)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    colors[currentPage].opacity(0.1),
                    Color(.systemBackground)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            // 自動進行タイマー（オプション）
            // Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            //     withAnimation {
            //         currentPage = (currentPage + 1) % pages.count
            //     }
            // }
        }
    }
}

#Preview {
    OnboardingView()
} 