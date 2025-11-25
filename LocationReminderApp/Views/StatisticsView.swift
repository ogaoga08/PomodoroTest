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
    @State private var selectedStartDate: Date?
    @State private var selectedTab = 0 // 0: 日ごと, 1: 週ごと
    
    // 統計データの開始日を取得または設定
    private var statisticsStartDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 完了タスクから最も古い日付を取得
        let oldestCompletedDate = taskManager.completedTasks
            .compactMap { $0.completedDate }
            .min()
        
        // スナップショットデータから最も古い日付を取得
        let oldestSnapshotDate = getOldestSnapshotDate()
        
        // 完了タスクとスナップショットの中で最も古い日付を使用
        let candidates = [oldestCompletedDate, oldestSnapshotDate].compactMap { $0 }
        
        if let oldestDate = candidates.min() {
            return calendar.startOfDay(for: oldestDate)
        } else {
            // データが何もない場合は今日を返す
            return today
        }
    }
    
    // スナップショットから最も古い日付を取得
    private func getOldestSnapshotDate() -> Date? {
        let key = "daily_stats_snapshots"
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([DailyStatsSnapshot].self, from: data) else {
            return nil
        }
        return snapshots.map { $0.date }.min()
    }
    
    // デフォルトの表示開始日を計算
    private var defaultDisplayStartDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let appStartDate = statisticsStartDate
        
        // アプリ開始日から今日までの日数
        let daysSinceStart = calendar.dateComponents([.day], from: appStartDate, to: today).day!
        
        if daysSinceStart >= 13 {
            // 14日以上経過している場合は、最新の2週間（今日から13日前）
            return calendar.date(byAdding: .day, value: -13, to: today)!
        } else {
            // 14日未満の場合は、アプリ利用開始日から
            return appStartDate
        }
    }
    
    // 表示する日付の配列を計算
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let baseStartDate = selectedStartDate ?? defaultDisplayStartDate
        
        // 選択された開始日から2週間後の日付
        let twoWeeksLater = calendar.date(byAdding: .day, value: 13, to: baseStartDate)!
        
        // 表示終了日は「開始日+13日」と「今日」のうち早い方
        let endDate = min(twoWeeksLater, today)
        
        // 開始日から終了日までの日数
        let dayCount = calendar.dateComponents([.day], from: baseStartDate, to: endDate).day! + 1
        
        // 開始日から昇順で日付を生成
        return (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: baseStartDate)
        }
    }
    
    // 選択可能な開始日の範囲（統計開始日から今日まで）
    private var availableStartDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = statisticsStartDate
        
        // 統計開始日から今日までの日数
        let dayCount = calendar.dateComponents([.day], from: startDate, to: today).day! + 1
        
        // 統計開始日から今日まで、全ての日付を選択可能にする
        return (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
        }
    }
    
    // 週ごとの統計データを計算
    private var weeklyStatistics: [WeeklyStatistics] {
        let baseStartDate = selectedStartDate ?? defaultDisplayStartDate
        let calendar = Calendar.current
        var result: [WeeklyStatistics] = []
        
        // 第1週（開始日から7日間）
        let week1Dates = (0..<7).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: baseStartDate),
                  weekDates.contains(date) else {
                return nil
            }
            return date
        }
        
        if !week1Dates.isEmpty {
            let week1Stats = week1Dates.map { getDailyStatistics(for: $0) }
            result.append(calculateWeeklyStats(
                weekNumber: 1,
                startDate: week1Dates.first!,
                endDate: week1Dates.last!,
                dailyStats: week1Stats
            ))
        }
        
        // 第2週（8日目から14日間）
        let week2Dates = (7..<14).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: baseStartDate),
                  weekDates.contains(date) else {
                return nil
            }
            return date
        }
        
        if !week2Dates.isEmpty {
            let week2Stats = week2Dates.map { getDailyStatistics(for: $0) }
            result.append(calculateWeeklyStats(
                weekNumber: 2,
                startDate: week2Dates.first!,
                endDate: week2Dates.last!,
                dailyStats: week2Stats
            ))
        }
        
        return result
    }
    
    // 週ごとの平均を計算
    private func calculateWeeklyStats(
        weekNumber: Int,
        startDate: Date,
        endDate: Date,
        dailyStats: [DailyStatistics]
    ) -> WeeklyStatistics {
        let dayCount = Double(dailyStats.count)
        
        // 完了タスク数の平均
        let totalCompleted = dailyStats.reduce(0) { $0 + $1.completedCount }
        let avgCompletedCount = dayCount > 0 ? Double(totalCompleted) / dayCount : 0
        
        // 制限時間の平均
        let totalRestriction = dailyStats.reduce(0.0) { $0 + $1.totalRestrictionTime }
        let avgRestrictionTime = dayCount > 0 ? totalRestriction / dayCount : 0
        
        // 入退室回数の平均
        let totalBubbleOutside = dailyStats.reduce(0) { $0 + $1.bubbleOutsideCount }
        let avgBubbleOutsideCount = dayCount > 0 ? Double(totalBubbleOutside) / dayCount : 0
        
        // 平均集中度の計算
        let allConcentrationLevels = dailyStats.flatMap { stat in
            stat.completedTasks.compactMap { $0.concentrationLevel }
        }
        let avgConcentration: Double? = !allConcentrationLevels.isEmpty
            ? Double(allConcentrationLevels.reduce(0, +)) / Double(allConcentrationLevels.count)
            : nil
        
        // タスク遂行時間差の平均を計算
        let allTimeDifferences = dailyStats.flatMap { stat in
            stat.completedTasks.map { task in
                task.completedDate.timeIntervalSince(task.dueDate)
            }
        }
        let avgCompletionTimeDifference: TimeInterval? = !allTimeDifferences.isEmpty
            ? allTimeDifferences.reduce(0, +) / Double(allTimeDifferences.count)
            : nil
        
        return WeeklyStatistics(
            weekNumber: weekNumber,
            startDate: startDate,
            endDate: endDate,
            avgCompletedCount: avgCompletedCount,
            avgRestrictionTime: avgRestrictionTime,
            avgBubbleOutsideCount: avgBubbleOutsideCount,
            avgConcentration: avgConcentration,
            avgCompletionTimeDifference: avgCompletionTimeDifference,
            dailyStats: dailyStats
        )
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 共通ヘッダー：開始日選択とCSVボタン
                VStack(spacing: 12) {
                    // 開始日選択セクション
                    VStack(spacing: 8) {
                        HStack {
                            Text("表示期間")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            
                            Picker("開始日", selection: Binding(
                                get: { selectedStartDate ?? defaultDisplayStartDate },
                                set: { selectedStartDate = $0 }
                            )) {
                                // 昇順で表示（古い→新しい）
                                ForEach(availableStartDates, id: \.self) { date in
                                    Text(formatPickerDate(date))
                                        .tag(date)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.subheadline)
                        }
                        .padding(.horizontal)
                        
                        // 選択された期間を表示
                        HStack {
                            Text(formatSelectedPeriod())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    
                    // CSVエクスポートボタン
                    HStack(spacing: 8) {
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
                    .padding(.top, 4)
                }
                .background(Color(.systemBackground))
                
                // タブ表示
                Picker("表示形式", selection: $selectedTab) {
                    Text("日ごと").tag(0)
                    Text("週ごと").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // コンテンツ
                TabView(selection: $selectedTab) {
                    // 日ごとタブ
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(weekDates, id: \.self) { date in
                                DayStatisticsCard(
                                    date: date,
                                    taskManager: taskManager
                                )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .tag(0)
                    
                    // 週ごとタブ
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(weeklyStatistics) { weekStat in
                                WeekStatisticsCard(weekStats: weekStat)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
    
    // 日付フォーマット用のヘルパー
    private var calendar: Calendar {
        Calendar.current
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func formatPickerDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func formatSelectedPeriod() -> String {
        let start = selectedStartDate ?? defaultDisplayStartDate
        let end = weekDates.last ?? start
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ja_JP")
        
        return "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"
    }
    
    // CSV生成（週ごと平均→日ごとデータ→完了タスクデータ）
    private func generateCSV() -> String {
        var csv = ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        print("📊 CSV生成開始")
        
        // 1. 週ごと平均データ
        csv += "週ごと平均データ\n"
        csv += "週,期間,平均完了タスク数,平均制限時間(分),平均入退室回数,平均集中度合い,平均遂行時間差(分)\n"
        
        for weekStat in weeklyStatistics {
            let startDate = dateFormatter.string(from: weekStat.startDate)
            let endDate = dateFormatter.string(from: weekStat.endDate)
            let avgRestrictionMinutes = Int(weekStat.avgRestrictionTime / 60)
            let avgConcentrationString = weekStat.avgConcentration.map { String(format: "%.1f", $0) } ?? ""
            let avgTimeDiffString = weekStat.avgCompletionTimeDifference.map { 
                String(format: "%.1f", $0 / 60) 
            } ?? ""
            
            csv += "第\(weekStat.weekNumber)週,\(startDate)〜\(endDate),\(String(format: "%.1f", weekStat.avgCompletedCount)),\(avgRestrictionMinutes),\(String(format: "%.1f", weekStat.avgBubbleOutsideCount)),\(avgConcentrationString),\(avgTimeDiffString)\n"
            print("📊 第\(weekStat.weekNumber)週: 平均完了\(String(format: "%.1f", weekStat.avgCompletedCount))件, 平均制限\(avgRestrictionMinutes)分")
        }
        
        // 2. 日ごとデータ
        csv += "\n日ごとデータ\n"
        csv += "日付,完了タスク数,アプリ制限時間(分),入退室回数,平均集中度合い\n"
        
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
            print("📊 \(dateString): タスク\(stats.completedCount)件, 制限\(restrictionMinutes)分, 入退室\(stats.bubbleOutsideCount)回")
        }
        
        // 3. 完了したタスクごとデータ
        csv += "\n完了したタスクごとデータ\n"
        csv += "日付,タスク名,通知時刻,完了時刻,集中度合い\n"
        
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
        
        return csv
    }
    
    // 日別統計データを取得
    private func getDailyStatistics(for date: Date) -> DailyStatistics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // 完了したタスクを取得（完了日ベース）
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
        
        // 完了数の決定（実際の数とスナップショットの大きい方を使用）
        let today = calendar.startOfDay(for: Date())
        let actualCount = completedTasks.count
        let snapshotCount = DailyStatsSnapshotHelper.loadCompletedCount(for: date)
        
        // 過去の日付：スナップショットと実際の数を比較して大きい方を使用
        // （タスク削除の場合はスナップショット、追加完了の場合は実際の数）
        let completedCount = date < today ? max(snapshotCount ?? 0, actualCount) : actualCount

        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            completedCount: completedCount,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount
        )
    }

    // アプリ制限中のBubble外回数をカウント
    // Screen Time制限アプリが未選択でも、タスク時刻以降〜完了までの仮想制限期間を含める
    private func countBubbleOutsideDuringRestriction(
        date: Date,
        bubbleSessions: [BubbleSession],
        restrictionSessions: [RestrictionSession]
    ) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        // 実際の制限セッションに加えて、仮想制限期間も生成
        let virtualRestrictionSessions = generateVirtualRestrictionSessions(for: date)
        let allRestrictionSessions = mergeRestrictionSessions(
            actual: restrictionSessions,
            virtual: virtualRestrictionSessions
        )
        
        // デバッグログ
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        print("📊 入退室回数集計: \(dateFormatter.string(from: date))")
        print("  - 実制限セッション数: \(restrictionSessions.count)")
        print("  - 仮想制限セッション数: \(virtualRestrictionSessions.count)")
        print("  - マージ後セッション数: \(allRestrictionSessions.count)")
        
        for (idx, session) in allRestrictionSessions.enumerated() {
            print("  - セッション\(idx + 1): \(timeFormatter.string(from: session.startTime)) - \(timeFormatter.string(from: session.endTime))")
        }
        
        for bubbleSession in bubbleSessions {
            guard bubbleSession.isOutside,
                  calendar.isDate(bubbleSession.startTime, inSameDayAs: date) else {
                continue
            }
            
            // このBubbleセッションが制限時間（実際または仮想）と重なっているかチェック
            for restrictionSession in allRestrictionSessions {
                if sessionsOverlap(
                    bubbleStart: bubbleSession.startTime,
                    bubbleEnd: bubbleSession.endTime,
                    restrictionStart: restrictionSession.startTime,
                    restrictionEnd: restrictionSession.endTime
                ) {
                    count += 1
                    print("  ✅ カウント: \(timeFormatter.string(from: bubbleSession.startTime)) - \(timeFormatter.string(from: bubbleSession.endTime))")
                    break
                }
            }
        }
        
        print("  📈 合計入退室回数: \(count)")
        
        return count
    }
    
    // 未完了タスクから仮想制限期間を生成
    // タスク時刻以降〜完了時刻（または日の終わり）までを制限期間とみなす
    private func generateVirtualRestrictionSessions(for date: Date) -> [RestrictionSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        var virtualSessions: [RestrictionSession] = []
        
        // 対象日のタスクを取得（時刻設定済みのもの）
        let tasksForDate = taskManager.getParentTasks().filter { task in
            calendar.isDate(task.dueDate, inSameDayAs: date) && task.hasTime
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        print("  🔍 仮想制限期間生成: 対象タスク数 \(tasksForDate.count)")
        
        for task in tasksForDate {
            let taskTime = task.dueDate
            
            // タスク時刻が対象日内にあることを確認
            guard taskTime >= startOfDay && taskTime < endOfDay else { continue }
            
            // 終了時刻を決定
            let endTime: Date
            let reason: String
            if let completedDate = task.completedDate,
               completedDate >= taskTime && completedDate < endOfDay {
                // 対象日内に完了している場合は完了時刻まで
                endTime = completedDate
                reason = "完了時刻"
            } else if !task.isCompleted {
                // 未完了の場合は日の終わりまで（または現在時刻まで）
                let now = Date()
                if calendar.isDate(now, inSameDayAs: date) {
                    endTime = min(now, endOfDay)
                    reason = "現在時刻"
                } else if date < calendar.startOfDay(for: now) {
                    // 過去の日付なら日の終わりまで
                    endTime = endOfDay
                    reason = "日の終わり（過去）"
                } else {
                    // 未来の日付ならスキップ
                    print("    ⏭️ スキップ: \(task.title) - 未来の日付")
                    continue
                }
            } else {
                // 別の日に完了している場合は日の終わりまで
                endTime = endOfDay
                reason = "日の終わり（別日完了）"
            }
            
            // 開始時刻より終了時刻が後の場合のみセッションを作成
            if endTime > taskTime {
                let session = RestrictionSession(
                    startTime: taskTime,
                    endTime: endTime,
                    duration: endTime.timeIntervalSince(taskTime),
                    taskId: task.id.uuidString
                )
                virtualSessions.append(session)
                print("    ✅ 仮想セッション作成: \(task.title)")
                print("       \(timeFormatter.string(from: taskTime)) - \(timeFormatter.string(from: endTime)) (\(reason))")
            }
        }
        
        return virtualSessions
    }
    
    // 実際の制限セッションと仮想制限セッションをマージ（重複を排除）
    private func mergeRestrictionSessions(
        actual: [RestrictionSession],
        virtual: [RestrictionSession]
    ) -> [RestrictionSession] {
        var allSessions = actual + virtual
        
        // 開始時刻でソート
        allSessions.sort { $0.startTime < $1.startTime }
        
        // 重複する期間をマージ
        var merged: [RestrictionSession] = []
        
        for session in allSessions {
            if merged.isEmpty {
                merged.append(session)
            } else {
                let last = merged[merged.count - 1]
                
                // 前のセッションと重なっている、または連続している場合はマージ
                if session.startTime <= last.endTime {
                    // より遅い終了時刻を採用
                    let newEndTime = max(last.endTime, session.endTime)
                    let newSession = RestrictionSession(
                        startTime: last.startTime,
                        endTime: newEndTime,
                        duration: newEndTime.timeIntervalSince(last.startTime),
                        taskId: last.taskId ?? session.taskId
                    )
                    merged[merged.count - 1] = newSession
                } else {
                    // 重ならない場合は新規追加
                    merged.append(session)
                }
            }
        }
        
        return merged
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

// 週別統計カード
struct WeekStatisticsCard: View {
    let weekStats: WeeklyStatistics
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 8) {
                HStack {
                    Text("第\(weekStats.weekNumber)週")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(dateFormatter.string(from: weekStats.startDate)) 〜 \(dateFormatter.string(from: weekStats.endDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 平均値サマリー
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatBadge(
                            icon: "checkmark.circle.fill",
                            value: String(format: "%.1f", weekStats.avgCompletedCount),
                            color: .green,
                            description: "平均完了"
                        )
                        
                        StatBadge(
                            icon: "hourglass",
                            value: formatMinutes(weekStats.avgRestrictionTime),
                            color: .blue,
                            description: "平均制限"
                        )
                        
                        StatBadge(
                            icon: "location.slash.fill",
                            value: String(format: "%.1f", weekStats.avgBubbleOutsideCount),
                            color: .orange,
                            description: "平均入退室"
                        )
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        if let avgConcentration = weekStats.avgConcentration {
                            StatBadge(
                                icon: "brain.head.profile",
                                value: String(format: "%.1f", avgConcentration),
                                color: concentrationColorForAverage(avgConcentration),
                                description: "平均集中度"
                            )
                        }
                        
                        if let avgTimeDiff = weekStats.avgCompletionTimeDifference {
                            StatBadge(
                                icon: "clock.arrow.circlepath",
                                value: formatTimeDifference(avgTimeDiff),
                                color: timeDifferenceColor(avgTimeDiff),
                                description: "平均遂行時間差"
                            )
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding()
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
    
    private func concentrationColorForAverage(_ avg: Double) -> Color {
        if avg >= 4.5 { return .green }
        else if avg >= 3.5 { return .blue }
        else if avg >= 2.5 { return .gray }
        else if avg >= 1.5 { return .orange }
        else { return .red }
    }
    
    private func formatTimeDifference(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        let absMinutes = abs(minutes)
        let sign = minutes >= 0 ? "+" : "-"
        
        if absMinutes >= 60 {
            let hours = absMinutes / 60
            let remainingMinutes = absMinutes % 60
            if remainingMinutes == 0 {
                return "\(sign)\(hours)h"
            }
            return "\(sign)\(hours)h\(remainingMinutes)m"
        } else {
            return "\(sign)\(absMinutes)m"
        }
    }
    
    private func timeDifferenceColor(_ timeInterval: TimeInterval) -> Color {
        let minutes = timeInterval / 60
        if minutes < -30 { return .purple } // 30分以上早い
        else if minutes < 0 { return .green } // 早め
        else if minutes < 30 { return .blue } // 30分以内の遅延
        else if minutes < 60 { return .orange } // 30分〜60分の遅延
        else { return .red } // 60分以上の遅延
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
        
        // 完了したタスクを取得（完了日ベース）
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
        
        // 完了数の決定（実際の数とスナップショットの大きい方を使用）
        let today = calendar.startOfDay(for: Date())
        let actualCount = completedTasks.count
        let snapshotCount = DailyStatsSnapshotHelper.loadCompletedCount(for: date)
        
        // 過去の日付：スナップショットと実際の数を比較して大きい方を使用
        // （タスク削除の場合はスナップショット、追加完了の場合は実際の数）
        let completedCount = date < today ? max(snapshotCount ?? 0, actualCount) : actualCount

        return DailyStatistics(
            date: date,
            completedTasks: completedTasks,
            completedCount: completedCount,
            totalRestrictionTime: totalRestrictionTime,
            bubbleOutsideCount: bubbleOutsideCount
        )
    }
    
    // アプリ制限中のBubble外回数をカウント（DayStatisticsCard用）
    // Screen Time制限アプリが未選択でも、タスク時刻以降〜完了までの仮想制限期間を含める
    private func countBubbleOutsideDuringRestriction(
        date: Date,
        bubbleSessions: [BubbleSession],
        restrictionSessions: [RestrictionSession]
    ) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        // 実際の制限セッションに加えて、仮想制限期間も生成
        let virtualRestrictionSessions = generateVirtualRestrictionSessions(for: date)
        let allRestrictionSessions = mergeRestrictionSessions(
            actual: restrictionSessions,
            virtual: virtualRestrictionSessions
        )
        
        for bubbleSession in bubbleSessions {
            guard bubbleSession.isOutside,
                  calendar.isDate(bubbleSession.startTime, inSameDayAs: date) else {
                continue
            }
            
            // このBubbleセッションが制限時間（実際または仮想）と重なっているかチェック
            for restrictionSession in allRestrictionSessions {
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
    
    // 未完了タスクから仮想制限期間を生成（DayStatisticsCard用）
    private func generateVirtualRestrictionSessions(for date: Date) -> [RestrictionSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        var virtualSessions: [RestrictionSession] = []
        
        // 対象日のタスクを取得（時刻設定済みのもの）
        let tasksForDate = taskManager.getParentTasks().filter { task in
            calendar.isDate(task.dueDate, inSameDayAs: date) && task.hasTime
        }
        
        for task in tasksForDate {
            let taskTime = task.dueDate
            
            // タスク時刻が対象日内にあることを確認
            guard taskTime >= startOfDay && taskTime < endOfDay else { continue }
            
            // 終了時刻を決定
            let endTime: Date
            if let completedDate = task.completedDate,
               completedDate >= taskTime && completedDate < endOfDay {
                // 対象日内に完了している場合は完了時刻まで
                endTime = completedDate
            } else if !task.isCompleted {
                // 未完了の場合は日の終わりまで（または現在時刻まで）
                let now = Date()
                if calendar.isDate(now, inSameDayAs: date) {
                    endTime = min(now, endOfDay)
                } else if date < calendar.startOfDay(for: now) {
                    // 過去の日付なら日の終わりまで
                    endTime = endOfDay
                } else {
                    // 未来の日付ならスキップ
                    continue
                }
            } else {
                // 別の日に完了している場合は日の終わりまで
                endTime = endOfDay
            }
            
            // 開始時刻より終了時刻が後の場合のみセッションを作成
            if endTime > taskTime {
                let session = RestrictionSession(
                    startTime: taskTime,
                    endTime: endTime,
                    duration: endTime.timeIntervalSince(taskTime),
                    taskId: task.id.uuidString
                )
                virtualSessions.append(session)
            }
        }
        
        return virtualSessions
    }
    
    // 実際の制限セッションと仮想制限セッションをマージ（DayStatisticsCard用）
    private func mergeRestrictionSessions(
        actual: [RestrictionSession],
        virtual: [RestrictionSession]
    ) -> [RestrictionSession] {
        var allSessions = actual + virtual
        
        // 開始時刻でソート
        allSessions.sort { $0.startTime < $1.startTime }
        
        // 重複する期間をマージ
        var merged: [RestrictionSession] = []
        
        for session in allSessions {
            if merged.isEmpty {
                merged.append(session)
            } else {
                let last = merged[merged.count - 1]
                
                // 前のセッションと重なっている、または連続している場合はマージ
                if session.startTime <= last.endTime {
                    // より遅い終了時刻を採用
                    let newEndTime = max(last.endTime, session.endTime)
                    let newSession = RestrictionSession(
                        startTime: last.startTime,
                        endTime: newEndTime,
                        duration: newEndTime.timeIntervalSince(last.startTime),
                        taskId: last.taskId ?? session.taskId
                    )
                    merged[merged.count - 1] = newSession
                } else {
                    // 重ならない場合は新規追加
                    merged.append(session)
                }
            }
        }
        
        return merged
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

// 週別統計データ構造
struct WeeklyStatistics: Identifiable {
    let id = UUID()
    let weekNumber: Int // 1 or 2
    let startDate: Date
    let endDate: Date
    let avgCompletedCount: Double
    let avgRestrictionTime: TimeInterval
    let avgBubbleOutsideCount: Double
    let avgConcentration: Double?
    let avgCompletionTimeDifference: TimeInterval? // タスク遂行時間差の平均（秒）
    let dailyStats: [DailyStatistics]
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
