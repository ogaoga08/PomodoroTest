import SwiftUI

struct StatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPeriod: StatisticsPeriod = .overview
    
    enum StatisticsPeriod: String, CaseIterable, Identifiable {
        case overview = "概要"
        case weekly = "週別"
        case monthly = "月別"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 期間選択
                    Picker("期間", selection: $selectedPeriod) {
                        ForEach(StatisticsPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    switch selectedPeriod {
                    case .overview:
                        OverviewStatisticsView(taskManager: taskManager)
                    case .weekly:
                        WeeklyStatisticsView(taskManager: taskManager)
                    case .monthly:
                        MonthlyStatisticsView(taskManager: taskManager)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("統計")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct OverviewStatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    
    private var statistics: EventKitTaskManager.TaskStatistics {
        taskManager.getDetailedStatistics()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // メイン統計カード（大きめ表示）
            VStack(spacing: 20) {
                Text("今日の状況")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 20) {
                    // 残りのタスク（赤ベース）
                    VStack(spacing: 8) {
                        Text("残りのタスク")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text("\(statistics.todayTasks)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    
                    // 期限遂行率（青ベース）
                    VStack(spacing: 8) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                Text("期限遂行率")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                        }
                        Text("\(Int(statistics.completionRate * 100))%")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // 全体統計カード
            VStack(spacing: 16) {
                Text("全体統計")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "総タスク数",
                        value: "\(statistics.totalTasks)",
                        color: .blue,
                        icon: "list.bullet"
                    )
                    
                    StatCard(
                        title: "未完了",
                        value: "\(statistics.pendingTasks)",
                        color: .orange,
                        icon: "clock"
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // 詳細統計
            VStack(spacing: 16) {
                Text("詳細統計")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 16) {
                    StatCard(
                        title: "今日完了",
                        value: "\(statistics.todayCompleted)",
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )
                    
                    StatCard(
                        title: "期限超過",
                        value: "\(statistics.overdueTasks)",
                        color: .red,
                        icon: "exclamationmark.triangle"
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // 優先度別統計
            VStack(spacing: 16) {
                Text("優先度別タスク数")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 12) {
                    PriorityBar(
                        title: "高優先度",
                        count: statistics.highPriorityTasks,
                        total: statistics.totalTasks,
                        color: .red
                    )
                    
                    PriorityBar(
                        title: "中優先度",
                        count: statistics.mediumPriorityTasks,
                        total: statistics.totalTasks,
                        color: .orange
                    )
                    
                    PriorityBar(
                        title: "低優先度",
                        count: statistics.lowPriorityTasks,
                        total: statistics.totalTasks,
                        color: .blue
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // 最近の活動
            VStack(spacing: 16) {
                Text("最近の活動")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "今週完了",
                        value: "\(statistics.weeklyCompleted)",
                        color: .green,
                        icon: "calendar.badge.checkmark"
                    )
                    
                    StatCard(
                        title: "今月完了",
                        value: "\(statistics.monthlyCompleted)",
                        color: .blue,
                        icon: "calendar.badge.checkmark"
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
}

struct WeeklyStatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    
    private var weeklyStats: [EventKitTaskManager.WeeklyStats] {
        taskManager.getWeeklyStatistics()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("過去8週間の統計")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            ForEach(weeklyStats.indices, id: \.self) { index in
                let stat = weeklyStats[index]
                WeeklyStatRow(
                    weekStart: stat.weekStart,
                    completed: stat.completed,
                    created: stat.created,
                    overdue: stat.overdue
                )
            }
        }
        .padding(.horizontal)
    }
}

struct MonthlyStatisticsView: View {
    @ObservedObject var taskManager: TaskManager
    
    private var monthlyStats: [EventKitTaskManager.MonthlyStats] {
        taskManager.getMonthlyStatistics()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("過去6ヶ月の統計")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            ForEach(monthlyStats.indices, id: \.self) { index in
                let stat = monthlyStats[index]
                MonthlyStatRow(
                    month: stat.month,
                    completed: stat.completed,
                    created: stat.created,
                    overdue: stat.overdue
                )
            }
        }
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 2, x: 0, y: 1)
    }
}

struct PriorityBar: View {
    let title: String
    let count: Int
    let total: Int
    let color: Color
    
    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

struct WeeklyStatRow: View {
    let weekStart: Date
    let completed: Int
    let created: Int
    let overdue: Int
    
    private var weekFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(weekFormatter.string(from: weekStart))の週")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack {
                    Text("\(completed)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("完了")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(created)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("作成")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(overdue)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("期限超過")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MonthlyStatRow: View {
    let month: Date
    let completed: Int
    let created: Int
    let overdue: Int
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(monthFormatter.string(from: month))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack {
                    Text("\(completed)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("完了")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(created)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("作成")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(overdue)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("期限超過")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    StatisticsView(taskManager: TaskManager())
} 
