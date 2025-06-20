import Foundation
import SwiftUI
import AVFoundation

enum TimerState {
    case idle
    case working
    case `break`
    case paused
}

class TimerManager: ObservableObject {
    @Published var timeRemaining: Int = 0
    @Published var timerState: TimerState = .idle
    @Published var workDuration: Int = 25
    @Published var breakDuration: Int = 5
    
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    
    var isRunning: Bool {
        timerState == .working || timerState == .break
    }
    
    var isPaused: Bool {
        timerState == .paused
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    init() {
        setupAudioPlayer()
    }
    
    private func setupAudioPlayer() {
        // システムサウンドを使用
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
            // システムサウンドファイルがない場合は、コード内でサウンドを生成
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to setup audio player: \(error)")
        }
    }
    
    func startWork() {
        timeRemaining = workDuration * 60
        timerState = .working
        startTimer()
    }
    
    func startBreak() {
        timeRemaining = breakDuration * 60
        timerState = .break
        startTimer()
    }
    
    func pauseTimer() {
        timer?.invalidate()
        timer = nil
        timerState = .paused
    }
    
    func resumeTimer() {
        if timerState == .paused {
            timerState = timeRemaining > 0 ? .working : .break
            startTimer()
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerState = .idle
        timeRemaining = 0
    }
    
    func stopAlarm() {
        audioPlayer?.stop()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.timerFinished()
            }
        }
    }
    
    private func timerFinished() {
        timer?.invalidate()
        timer = nil
        
        // アラーム音を再生
        playAlarm()
        
        // 作業時間が終了したら休憩時間に移行
        if timerState == .working {
            startBreak()
        } else {
            timerState = .idle
        }
    }
    
    private func playAlarm() {
        // システムサウンドを再生
        AudioServicesPlaySystemSound(1005) // システムアラート音
        
        // カスタムサウンドがある場合
        audioPlayer?.play()
    }
}

import AudioToolbox 
