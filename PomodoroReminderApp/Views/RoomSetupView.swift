import SwiftUI

struct RoomSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uwbManager = UWBManager.shared
    @State private var currentPage = 0
    @State private var savedDoorDistance: Float? = UserDefaults.standard.object(forKey: "door_distance") as? Float
    @State private var showingSuccessMessage = false
    
    private let setupSteps = [
        SetupStep(
            title: "部屋の範囲設定を行います",
            description: "UWBモジュールを使って部屋への入退室を自動検知します。",
            systemImage: "house.circle"
        ),
        SetupStep(
            title: "UWBモジュールを設置",
            description: "UWBモジュールをドアから一番離れた安定した場所に設置してください。",
            systemImage: "dot.radiowaves.left.and.right"
        ),
        SetupStep(
            title: "ドア位置での距離設定",
            description: "ドアの場所に立ち、「設定」ボタンを押してください。",
            systemImage: "door.left.hand.open"
        )
    ]
    
    var roomStatus: String {
        guard let savedDistance = savedDoorDistance,
              let currentDistance = uwbManager.currentDistance else {
            return "未設定"
        }
        
        return currentDistance <= savedDistance ? "入室中" : "外出中"
    }
    
    var roomStatusColor: Color {
        switch roomStatus {
        case "入室中":
            return .green
        case "外出中":
            return .orange
        default:
            return .gray
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // カルーセル
                TabView(selection: $currentPage) {
                    ForEach(0..<setupSteps.count, id: \.self) { index in
                        setupStepView(setupSteps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .frame(height: 300)
                
                // 距離表示と設定エリア
                VStack(spacing: 16) {
                    // 現在の距離表示
                    VStack(spacing: 8) {
                        Text("現在の測定距離")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(uwbManager.currentDistance != nil ? 
                             String(format: "%.2fm", uwbManager.currentDistance!) : 
                             "-.--m")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(uwbManager.isUWBActive ? .primary : .gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // 設定済み距離と状態表示
                    if let savedDistance = savedDoorDistance {
                        VStack(spacing: 8) {
                            Text("設定済みドア距離: \(String(format: "%.2fm", savedDistance))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Circle()
                                    .fill(roomStatusColor)
                                    .frame(width: 12, height: 12)
                                Text(roomStatus)
                                    .font(.headline)
                                    .foregroundColor(roomStatusColor)
                            }
                        }
                        .padding()
                        .background(roomStatusColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Secure Bubble状態表示
                    if uwbManager.isUWBActive {
                        VStack(spacing: 8) {
                            Text("Secure Bubble状態")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: uwbManager.isInSecureBubble ? "checkmark.shield.fill" : "xmark.shield.fill")
                                    .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
                                Text(uwbManager.isInSecureBubble ? "内部 (0.2m以内)" : "外部 (1.2m以上)")
                                    .font(.headline)
                                    .foregroundColor(uwbManager.isInSecureBubble ? .green : .red)
                            }
                        }
                        .padding()
                        .background(uwbManager.isInSecureBubble ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // 設定ボタン
                    Button(action: saveDoorDistance) {
                        HStack {
                            Image(systemName: "location.circle")
                            Text(savedDoorDistance == nil ? "距離を設定" : "距離を再設定")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(uwbManager.currentDistance != nil ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(uwbManager.currentDistance == nil)
                    
                    // UWB接続状況
                    if !uwbManager.isUWBActive {
                        Text("⚠️ UWBモジュールが接続されていません")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("部屋設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .alert("設定完了", isPresented: $showingSuccessMessage) {
            Button("OK") { }
        } message: {
            Text("ドアの距離が設定されました。今後、この距離を基準に入退室を判定します。")
        }
    }
    
    private func setupStepView(_ step: SetupStep) -> some View {
        VStack(spacing: 24) {
            Image(systemName: step.systemImage)
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding()
    }
    
    private func saveDoorDistance() {
        guard let currentDistance = uwbManager.currentDistance else { return }
        
        savedDoorDistance = currentDistance
        UserDefaults.standard.set(currentDistance, forKey: "door_distance")
        showingSuccessMessage = true
        
        // ハプティックフィードバック
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

struct SetupStep {
    let title: String
    let description: String
    let systemImage: String
}

#Preview {
    RoomSetupView()
} 