import SwiftUI
import UIKit

struct StatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    
    @State private var showShareSheet = false
    @State private var csvText = ""
    @State private var showCopiedAlert = false
    
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
                        
                        // 共有シート
                        Button(action: {
                            csvText = generateCSV()
                            showShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("共有")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
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
                // 統計画面表示時にカテゴリー別データの取得をリクエスト
                screenTimeManager.requestCategoryUsageData()
            }
        }
    }
    
    // CSV生成（1週間分）
    private func generateCSV() -> String {
        var csv = "日付,完了タスク数,アプリ制限時間(分),総使用時間(分),Bubble外回数\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        print("📊 CSV生成開始")
        print("📊 週間日付数: \(weekDates.count)")
        
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            let restrictionMinutes = Int(stats.totalRestrictionTime / 60)
            let usageMinutes = Int(stats.totalUsageTime / 60)
            csv += "\(dateString),\(stats.completedTasks.count),\(restrictionMinutes),\(usageMinutes),\(stats.bubbleOutsideCount)\n"
            print("📊 \(dateString): タスク\(stats.completedTasks.count)件, 制限\(restrictionMinutes)分, 使用\(usageMinutes)分, Bubble外\(stats.bubbleOutsideCount)回")
        }
        
        csv += "\nカテゴリー別使用時間\n"
        csv += "日付,カテゴリー名,使用時間(分)\n"
        
        var categoryCount = 0
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            
            for category in stats.categoryUsageData {
                let usageMinutes = Int(category.totalTime / 60)
                csv += "\(dateString),\(category.categoryName),\(usageMinutes)\n"
                categoryCount += 1
            }
        }
        
        csv += "\n完了したタスク\n"
        csv += "日付,タスク名,登録時刻,完了時刻\n"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        var taskCount = 0
        for date in weekDates {
            let stats = getDailyStatistics(for: date)
            let dateString = dateFormatter.string(from: date)
            
            for task in stats.completedTasks {
                let createdTimeString = task.creationDate != nil ? timeFormatter.string(from: task.creationDate!) : "不明"
                let completedTimeString = timeFormatter.string(from: task.completedDate)
                csv += "\(dateString),\(task.title),\(createdTimeString),\(completedTimeString)\n"
                taskCount += 1
            }
        }
        
        print("📊 完了タスク総数: \(taskCount)件")
        print("📊 カテゴリーデータ総数: \(categoryCount)件")
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
        
        // カテゴリー別使用時間データを取得
        let usageData = getDailyUsageData(for: date)
        
        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount,
            totalUsageTime: usageData.totalUsageTime,
            categoryUsageData: usageData.categoryData
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
    
    // App Groupsからカテゴリー別使用時間データを取得
    private func getDailyUsageData(for date: Date) -> DailyUsageData {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.locationreminder.app.screentime"),
              let data = appGroupDefaults.data(forKey: "daily_usage_data"),
              let dailyUsageDataArray = try? JSONDecoder().decode([DailyUsageData].self, from: data) else {
            print("📊 カテゴリー別データが見つかりません")
            return DailyUsageData(date: date, totalUsageTime: 0, categoryData: [])
        }
        
        // 指定された日付のデータを検索
        let calendar = Calendar.current
        if let matchingData = dailyUsageDataArray.first(where: { 
            calendar.isDate($0.date, inSameDayAs: date) 
        }) {
            print("📊 カテゴリー別データを取得: \(matchingData.categoryData.count)カテゴリー")
            return matchingData
        }
        
        print("📊 指定日付のカテゴリー別データが見つかりません: \(date)")
        return DailyUsageData(date: date, totalUsageTime: 0, categoryData: [])
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
                            icon: "iphone",
                            value: formatMinutes(statistics.totalUsageTime),
                            color: .purple
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
                    // カテゴリー別使用時間
                    if !statistics.categoryUsageData.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("カテゴリー別使用時間")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ForEach(statistics.categoryUsageData.prefix(3), id: \.categoryName) { category in
                                CategoryUsageRow(category: category)
                            }
                            
                            if statistics.categoryUsageData.count > 3 {
                                Text("他 \(statistics.categoryUsageData.count - 3) カテゴリー")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    
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
        
        // カテゴリー別使用時間データを取得
        let usageData = getDailyUsageData(for: date)
        
        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount,
            totalUsageTime: usageData.totalUsageTime,
            categoryUsageData: usageData.categoryData
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
    
    // App Groupsからカテゴリー別使用時間データを取得
    private func getDailyUsageData(for date: Date) -> DailyUsageData {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.locationreminder.app.screentime"),
              let data = appGroupDefaults.data(forKey: "daily_usage_data"),
              let dailyUsageDataArray = try? JSONDecoder().decode([DailyUsageData].self, from: data) else {
            print("📊 カテゴリー別データが見つかりません")
            return DailyUsageData(date: date, totalUsageTime: 0, categoryData: [])
        }
        
        // 指定された日付のデータを検索
        let calendar = Calendar.current
        if let matchingData = dailyUsageDataArray.first(where: { 
            calendar.isDate($0.date, inSameDayAs: date) 
        }) {
            print("📊 カテゴリー別データを取得: \(matchingData.categoryData.count)カテゴリー")
            return matchingData
        }
        
        print("📊 指定日付のカテゴリー別データが見つかりません: \(date)")
        return DailyUsageData(date: date, totalUsageTime: 0, categoryData: [])
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

// カテゴリー別使用時間行
struct CategoryUsageRow: View {
    let category: CategoryUsageData
    
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
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "apps.iphone")
                .font(.caption)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.categoryName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(formatMinutes(category.totalTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// 日別統計データ構造
struct DailyStatistics {
    let date: Date
    let completedTasks: [CompletedTaskInfo]
    let totalRestrictionTime: TimeInterval
    let bubbleOutsideCount: Int
    let totalUsageTime: TimeInterval
    let categoryUsageData: [CategoryUsageData]
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

// カテゴリー別使用時間データ構造（エクステンションと同じ）
struct CategoryUsageData: Codable {
    let categoryName: String
    let totalTime: TimeInterval
    let appCount: Int
    let date: Date
}

struct DailyUsageData: Codable {
    let date: Date
    let totalUsageTime: TimeInterval
    let categoryData: [CategoryUsageData]
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
