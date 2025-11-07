import SwiftUI
import UIKit

// 日別スナップショットヘルパー（ファイルレベル）
fileprivate struct DailyStatsSnapshot: Codable {
    let date: Date
    let completedCount: Int
}

fileprivate struct DailyStatsSnapshotHelper {
    private static let key = "daily_stats_snapshots"
    
    static func loadCompletedCount(for date: Date) -> Int? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([DailyStatsSnapshot].self, from: data) else {
            return nil
        }
        let calendar = Calendar.current
        return snapshots.first { calendar.isDate($0.date, inSameDayAs: date) }?.completedCount
    }
    
    static func upsertSnapshot(for date: Date, completedCount: Int) {
        var all = loadAll()
        let calendar = Calendar.current
        if let idx = all.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            all[idx] = DailyStatsSnapshot(date: calendar.startOfDay(for: date), completedCount: completedCount)
        } else {
            all.append(DailyStatsSnapshot(date: calendar.startOfDay(for: date), completedCount: completedCount))
        }
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        all = all.filter { $0.date >= ninetyDaysAgo }
        saveAll(all)
    }
    
    private static func loadAll() -> [DailyStatsSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DailyStatsSnapshot].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private static func saveAll(_ snapshots: [DailyStatsSnapshot]) {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct StatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    
    @State private var showShareSheet = false
    @State private var csvText = ""
    @State private var showCopiedAlert = false
    
    // 今日から過去13日分（計14日分）
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.reversed()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // CSVエクスポートボタン（横並び）
                    HStack(spacing: 8) {
                        // クリップボードにコピー
                        Button(action: {
                            csvText = generateCSV()
                            UIPasteboard.general.string = csvText
                            showCopiedAlert = true
                            print("✅ CSVをクリップボードにコピーしました")
                        }) {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("コピー")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        
                        
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
            .alert("コピー完了", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("CSVデータをクリップボードにコピーしました")
            }
            .onAppear {
                // 過去14日分のスナップショットを確定（今日以外）
                ensurePastSnapshots()
            }
        }
    }
    
    // CSV生成（1週間分）
    private func generateCSV() -> String {
        var csv = "日付,完了タスク数,アプリ制限時間(分),Bubble外回数,平均集中度合い\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        print("📊 CSV生成開始")
        print("📊 週間日付数: \(weekDates.count)")
        
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            let restrictionMinutes = Int(stats.totalRestrictionTime / 60)
            
            // 平均集中度合いを計算
            let tasksWithConcentration = stats.completedTasks.compactMap { $0.concentrationLevel }
            let avgConcentration: String
            if !tasksWithConcentration.isEmpty {
                let sum = tasksWithConcentration.reduce(0, +)
                let avg = Double(sum) / Double(tasksWithConcentration.count)
                avgConcentration = String(format: "%.1f", avg)
            } else {
                avgConcentration = ""
            }
            
            csv += "\(dateString),\(stats.completedCount),\(restrictionMinutes),\(stats.bubbleOutsideCount),\(avgConcentration)\n"
            print("📊 \(dateString): タスク\(stats.completedTasks.count)件, 制限\(restrictionMinutes)分, Bubble外\(stats.bubbleOutsideCount)回, 平均集中度\(avgConcentration)")
        }
        
        csv += "\n完了したタスク\n"
        csv += "日付,タスク名,通知時刻,完了時刻,集中度合い\n"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        var taskCount = 0
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            
            for task in stats.completedTasks {
                let dueTimeString = timeFormatter.string(from: task.dueDate)
                let completedTimeString = timeFormatter.string(from: task.completedDate)
                let concentrationString = task.concentrationLevel.map { String($0) } ?? ""
                csv += "\(dateString),\(task.title),\(dueTimeString),\(completedTimeString),\(concentrationString)\n"
                taskCount += 1
            }
        }
        
        print("📊 完了タスク総数: \(taskCount)件")
        print("📊 CSV文字数: \(csv.count)")
        print("📊 CSV内容:\n\(csv)")
        
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
                dueDate: task.dueDate,
                completedDate: completedDate,
                concentrationLevel: task.concentrationLevel
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
        
        // 完了数は日跨ぎ後はスナップショットを優先
        let today = calendar.startOfDay(for: Date())
        let snapshotCount = DailyStatsSnapshotHelper.loadCompletedCount(for: date)
        let completedCount = date < today ? (snapshotCount ?? completedTasks.count) : completedTasks.count

        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            completedCount: completedCount,
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
    
    // MARK: - スナップショット関連
    private func ensurePastSnapshots() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        print("📸 スナップショット確認開始")
        
        // 過去14日分（今日を除く）をチェック
        for offset in 1..<15 {
            guard let pastDate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            
            // スナップショットが存在しない場合のみ保存
            if DailyStatsSnapshotHelper.loadCompletedCount(for: pastDate) == nil {
                let stats = getDailyStatistics(for: pastDate)
                DailyStatsSnapshotHelper.upsertSnapshot(for: pastDate, completedCount: stats.completedTasks.count)
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy/MM/dd"
                print("📸 \(dateFormatter.string(from: pastDate)): スナップショット保存 (\(stats.completedTasks.count)件)")
            }
        }
        
        print("📸 スナップショット確認完了")
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
    
    private var averageConcentration: Double? {
        let tasksWithConcentration = statistics.completedTasks.compactMap { $0.concentrationLevel }
        guard !tasksWithConcentration.isEmpty else { return nil }
        let sum = tasksWithConcentration.reduce(0, +)
        return Double(sum) / Double(tasksWithConcentration.count)
    }
    
    private func concentrationColorForAverage(_ avg: Double) -> Color {
        if avg >= 4.5 { return .green }
        else if avg >= 3.5 { return .blue }
        else if avg >= 2.5 { return .gray }
        else if avg >= 1.5 { return .orange }
        else { return .red }
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
                            value: "\(statistics.completedCount)",
                            color: .green,
                            description: "完了タスク"
                        )
                        
                        StatBadge(
                            icon: "hourglass",
                            value: formatMinutes(statistics.totalRestrictionTime),
                            color: .blue,
                            description: "制限時間"
                        )
                        
                        StatBadge(
                            icon: "location.slash.fill",
                            value: "\(statistics.bubbleOutsideCount)",
                            color: .orange,
                            description: "入退室回数"
                        )
                        
                        // 平均集中度合い
                        if let avgConcentration = averageConcentration {
                            StatBadge(
                                icon: "brain.head.profile",
                                value: String(format: "%.1f", avgConcentration),
                                color: concentrationColorForAverage(avgConcentration),
                                description: "平均集中度"
                            )
                        }
                        
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
                    // 完了したタスク
                    if statistics.completedTasks.isEmpty {
                        Text("完了したタスクはありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("完了したタスク")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ForEach(statistics.completedTasks) { task in
                                CompactTaskRow(task: task)
                            }
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
                dueDate: task.dueDate,
                completedDate: completedDate,
                concentrationLevel: task.concentrationLevel
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
        
        // 完了数（過去日はスナップショット優先）
        let today = calendar.startOfDay(for: Date())
        let snapshotCount = DailyStatsSnapshotHelper.loadCompletedCount(for: date)
        let completedCount = date < today ? (snapshotCount ?? completedTasks.count) : completedTasks.count

        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            completedCount: completedCount,
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
    let description: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                    .fixedSize()
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
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
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    // 集中度合いバッジ
                    if let level = task.concentrationLevel {
                        HStack(spacing: 2) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10))
                            Text("\(level)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(concentrationColor(level))
                        .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 8) {
                    Label(timeFormatter.string(from: task.dueDate), systemImage: "bell")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Label(timeFormatter.string(from: task.completedDate), systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(isCompletedOnTime(task: task) ? .green : .red)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func concentrationColor(_ level: Int) -> Color {
        switch level {
        case 5: return .green
        case 4: return .blue
        case 3: return .gray
        case 2: return .orange
        case 1: return .red
        default: return .gray
        }
    }
    
    private func isCompletedOnTime(task: CompletedTaskInfo) -> Bool {
        let calendar = Calendar.current
        let dueDay = calendar.startOfDay(for: task.dueDate)
        let completedDay = calendar.startOfDay(for: task.completedDate)
        return completedDay <= dueDay
    }
}

// 日別統計データ構造
struct DailyStatistics {
    let date: Date
    let completedTasks: [CompletedTaskInfo]
    let completedCount: Int
    let totalRestrictionTime: TimeInterval
    let bubbleOutsideCount: Int
}

struct CompletedTaskInfo: Identifiable {
    let id = UUID()
    let title: String
    let dueDate: Date  // 通知時刻（登録時刻）
    let completedDate: Date
    let concentrationLevel: Int? // 集中度合い
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
        print("📋 ActivityViewController 作成")
        print("📋 共有アイテム数: \(activityItems.count)")
        
        for (index, item) in activityItems.enumerated() {
            if let text = item as? String {
                print("📋 アイテム[\(index)] テキスト長: \(text.count)文字")
                print("📋 アイテム[\(index)] 最初の100文字: \(String(text.prefix(100)))")
            } else {
                print("📋 アイテム[\(index)] タイプ: \(type(of: item))")
            }
        }
        
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
