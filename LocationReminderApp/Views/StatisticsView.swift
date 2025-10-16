import SwiftUI

struct StatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showShareSheet = false
    @State private var csvText = ""
    
    // 今日から過去6日分（計7日分）
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.reversed()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // CSVエクスポートボタン
                    Button(action: {
                        csvText = generateCSV()
                        showShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("CSVをエクスポート")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // 1週間分の統計
                    ForEach(weekDates, id: \.self) { date in
                        DayStatisticsCard(
                            date: date,
                            taskManager: taskManager
                        )
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("週間統計")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: [csvText])
            }
        }
    }
    
    // CSV生成（1週間分）
    private func generateCSV() -> String {
        var csv = "日付,完了タスク数,アプリ制限時間(分),Bubble外回数\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            let restrictionMinutes = Int(stats.totalRestrictionTime / 60)
            csv += "\(dateString),\(stats.completedTasks.count),\(restrictionMinutes),\(stats.bubbleOutsideCount)\n"
        }
        
        csv += "\n完了したタスク\n"
        csv += "日付,タスク名,登録時刻,完了時刻\n"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            
            for task in stats.completedTasks {
                let createdTimeString = task.creationDate != nil ? timeFormatter.string(from: task.creationDate!) : "不明"
                let completedTimeString = timeFormatter.string(from: task.completedDate)
                csv += "\(dateString),\(task.title),\(createdTimeString),\(completedTimeString)\n"
            }
        }
        
        return csv
    }
    
    // 日別統計データを取得
    private func getDailyStatistics(for date: Date) -> DailyStatistics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // 完了したタスクを取得
        let completedTasks = taskManager.completedTasks.compactMap { task -> CompletedTaskInfo? in
            guard let completedDate = task.completedDate,
                  completedDate >= startOfDay && completedDate < endOfDay else {
                return nil
            }
            return CompletedTaskInfo(
                title: task.title,
                creationDate: task.creationDate,
                completedDate: completedDate
            )
        }.sorted { $0.completedDate < $1.completedDate }
        
        // アプリ制限時間を取得
        let restrictionSessions = getRestrictionSessions()
        let totalRestrictionTime = restrictionSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .reduce(0.0) { $0 + $1.duration }
        
        // Bubble外回数を取得（アプリ制限中のみ）
        let bubbleSessions = getBubbleSessions()
        let bubbleOutsideCount = countBubbleOutsideDuringRestriction(
            date: date,
            bubbleSessions: bubbleSessions,
            restrictionSessions: restrictionSessions
        )
        
        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount
        )
    }
    
    // アプリ制限中のBubble外回数をカウント
    private func countBubbleOutsideDuringRestriction(
        date: Date,
        bubbleSessions: [BubbleSession],
        restrictionSessions: [RestrictionSession]
    ) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        for bubbleSession in bubbleSessions {
            guard bubbleSession.isOutside,
                  calendar.isDate(bubbleSession.startTime, inSameDayAs: date) else {
                continue
            }
            
            // このBubbleセッションが制限時間と重なっているかチェック
            for restrictionSession in restrictionSessions {
                if sessionsOverlap(
                    bubbleStart: bubbleSession.startTime,
                    bubbleEnd: bubbleSession.endTime,
                    restrictionStart: restrictionSession.startTime,
                    restrictionEnd: restrictionSession.endTime
                ) {
                    count += 1
                    break
                }
            }
        }
        
        return count
    }
    
    // セッションの重なりをチェック
    private func sessionsOverlap(
        bubbleStart: Date,
        bubbleEnd: Date,
        restrictionStart: Date,
        restrictionEnd: Date
    ) -> Bool {
        return bubbleStart < restrictionEnd && bubbleEnd > restrictionStart
    }
    
    // UserDefaultsからセッションデータを取得
    private func getRestrictionSessions() -> [RestrictionSession] {
        guard let data = UserDefaults.standard.data(forKey: "screen_time_restriction_sessions"),
              let sessions = try? JSONDecoder().decode([RestrictionSession].self, from: data) else {
            return []
        }
        return sessions
    }
    
    private func getBubbleSessions() -> [BubbleSession] {
        guard let data = UserDefaults.standard.data(forKey: "uwb_bubble_sessions"),
              let sessions = try? JSONDecoder().decode([BubbleSession].self, from: data) else {
            return []
        }
        return sessions
    }
}

// 日別統計カード（コンパクト版）
struct DayStatisticsCard: View {
    let date: Date
    @ObservedObject var taskManager: TaskManager
    
    @State private var isExpanded: Bool = false
    
    private var statistics: DailyStatistics {
        getDailyStatistics(for: date)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー部分
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(spacing: 8) {
                    HStack {
                        // 日付
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateFormatter.string(from: date))
                                .font(.headline)
                                .foregroundColor(isToday ? .blue : .primary)
                            if isToday {
                                Text("今日")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // サマリー（バッジを横一列に）
                    HStack(spacing: 8) {
                        StatBadge(
                            icon: "checkmark.circle.fill",
                            value: "\(statistics.completedTasks.count)",
                            color: .green
                        )
                        
                        StatBadge(
                            icon: "hourglass",
                            value: formatMinutes(statistics.totalRestrictionTime),
                            color: .blue
                        )
                        
                        StatBadge(
                            icon: "location.slash.fill",
                            value: "\(statistics.bubbleOutsideCount)",
                            color: .orange
                        )
                        
                        Spacer()
                    }
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            // 展開部分
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    if statistics.completedTasks.isEmpty {
                        Text("完了したタスクはありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(statistics.completedTasks) { task in
                            CompactTaskRow(task: task)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
    
    private func formatMinutes(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h\(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // 日別統計データを取得
    private func getDailyStatistics(for date: Date) -> DailyStatistics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let completedTasks = taskManager.completedTasks.compactMap { task -> CompletedTaskInfo? in
            guard let completedDate = task.completedDate,
                  completedDate >= startOfDay && completedDate < endOfDay else {
                return nil
            }
            return CompletedTaskInfo(
                title: task.title,
                creationDate: task.creationDate,
                completedDate: completedDate
            )
        }.sorted { $0.completedDate < $1.completedDate }
        
        let restrictionSessions = getRestrictionSessions()
        let totalRestrictionTime = restrictionSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .reduce(0.0) { $0 + $1.duration }
        
        let bubbleSessions = getBubbleSessions()
        let bubbleOutsideCount = countBubbleOutsideDuringRestriction(
            date: date,
            bubbleSessions: bubbleSessions,
            restrictionSessions: restrictionSessions
        )
        
        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount
        )
    }
    
    private func countBubbleOutsideDuringRestriction(
        date: Date,
        bubbleSessions: [BubbleSession],
        restrictionSessions: [RestrictionSession]
    ) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        for bubbleSession in bubbleSessions {
            guard bubbleSession.isOutside,
                  calendar.isDate(bubbleSession.startTime, inSameDayAs: date) else {
                continue
            }
            
            for restrictionSession in restrictionSessions {
                if sessionsOverlap(
                    bubbleStart: bubbleSession.startTime,
                    bubbleEnd: bubbleSession.endTime,
                    restrictionStart: restrictionSession.startTime,
                    restrictionEnd: restrictionSession.endTime
                ) {
                    count += 1
                    break
                }
            }
        }
        
        return count
    }
    
    private func sessionsOverlap(
        bubbleStart: Date,
        bubbleEnd: Date,
        restrictionStart: Date,
        restrictionEnd: Date
    ) -> Bool {
        return bubbleStart < restrictionEnd && bubbleEnd > restrictionStart
    }
    
    private func getRestrictionSessions() -> [RestrictionSession] {
        guard let data = UserDefaults.standard.data(forKey: "screen_time_restriction_sessions"),
              let sessions = try? JSONDecoder().decode([RestrictionSession].self, from: data) else {
            return []
        }
        return sessions
    }
    
    private func getBubbleSessions() -> [BubbleSession] {
        guard let data = UserDefaults.standard.data(forKey: "uwb_bubble_sessions"),
              let sessions = try? JSONDecoder().decode([BubbleSession].self, from: data) else {
            return []
        }
        return sessions
    }
}

// コンパクトな統計バッジ
struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }
}

// コンパクトなタスク行
struct CompactTaskRow: View {
    let task: CompletedTaskInfo
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let creationDate = task.creationDate {
                        Label(timeFormatter.string(from: creationDate), systemImage: "plus.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Label(timeFormatter.string(from: task.completedDate), systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// 日別統計データ構造
struct DailyStatistics {
    let date: Date
    let completedTasks: [CompletedTaskInfo]
    let totalRestrictionTime: TimeInterval
    let bubbleOutsideCount: Int
}

struct CompletedTaskInfo: Identifiable {
    let id = UUID()
    let title: String
    let creationDate: Date?
    let completedDate: Date
}

// セッションデータ構造
struct RestrictionSession: Codable {
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let taskId: String?
}

struct BubbleSession: Codable {
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let isOutside: Bool
    let taskId: String?
}

// ShareSheetのためのUIViewControllerRepresentable
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    StatisticsView(taskManager: TaskManager())
}
