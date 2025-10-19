//
//  TotalActivityReport.swift
//  ScreenTimeReport
//
//  Created by 小笠原慎 on 2025/10/17.
//

import DeviceActivity
import ExtensionKit
import SwiftUI
import FamilyControls

// カテゴリー別使用時間データ構造
public struct CategoryUsageData: Codable {
    public let categoryName: String
    public let totalTime: TimeInterval
    public let appCount: Int
    public let date: Date
    
    public init(categoryName: String, totalTime: TimeInterval, appCount: Int, date: Date) {
        self.categoryName = categoryName
        self.totalTime = totalTime
        self.appCount = appCount
        self.date = date
    }
}

public struct DailyUsageData: Codable {
    public let date: Date
    public let totalUsageTime: TimeInterval
    public let categoryData: [CategoryUsageData]
    
    public init(date: Date, totalUsageTime: TimeInterval, categoryData: [CategoryUsageData]) {
        self.date = date
        self.totalUsageTime = totalUsageTime
        self.categoryData = categoryData
    }
}

// TotalActivityReport.swift
extension DeviceActivityReport.Context {
    // If your app initializes a DeviceActivityReport with this context, then the system will use
    // your extension's corresponding DeviceActivityReportScene to render the contents of the
    // report.
    static let barGraph = Self("barGraph")
    static let pieChart = Self("pieChart")
    static let categoryData = Self("categoryData")
}

@MainActor
struct TotalActivityReport: DeviceActivityReportScene {
    // Define which context your scene will represent.
    let context: DeviceActivityReport.Context
    
    // Define the custom configuration and the resulting view for this report.
    let content: (String) -> TotalActivityView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        // Reformat the data into a configuration that can be used to create
        // the report's view.
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        
        switch context {
        case .categoryData:
            // カテゴリー別データを処理してApp Groupsに保存
            await processCategoryData(data)
            return "Category data processed"
            
        default:
            // 従来の総使用時間計算
            let totalActivityDuration = await data.flatMap { $0.activitySegments }.reduce(0, {
                $0 + $1.totalActivityDuration
            })
            return formatter.string(from: totalActivityDuration) ?? "No activity data"
        }
    }
    
    // カテゴリー別データを処理してApp Groupsに保存
    private func processCategoryData(_ data: DeviceActivityResults<DeviceActivityData>) async {
        print("📊 カテゴリー別データ処理開始")
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // カテゴリー別の使用時間を集計
        var categoryUsageMap: [String: TimeInterval] = [:]
        var totalUsageTime: TimeInterval = 0
        
        // DeviceActivityResultsを正しく処理（Qiitaの記事を参考）
        var firstData: DeviceActivityData?
        for await item in data {
            firstData = item
            break // 個人開発の場合は1つのデータのみ
        }
        
        if let segments = firstData?.activitySegments {
            for await segment in segments {
                totalUsageTime += segment.totalActivityDuration
                
                // カテゴリー別の使用時間を集計（Qiitaの記事を参考）
                var categoryData: DeviceActivityData.CategoryActivity?
                for await category in segment.categories {
                    categoryData = category
                    break // 個人開発の場合は1つのカテゴリーデータのみ
                }
                
                if let category = categoryData {
                    let categoryName = getCategoryDisplayName(category)
                    categoryUsageMap[categoryName, default: 0] += category.totalActivityDuration
                }
            }
        }
        
        // カテゴリーデータを配列に変換
        let categoryData = categoryUsageMap.map { (name, time) in
            CategoryUsageData(
                categoryName: name,
                totalTime: time,
                appCount: 0, // アプリ数は別途取得が必要
                date: today
            )
        }.sorted { $0.totalTime > $1.totalTime }
        
        // 日別データを作成
        let dailyData = DailyUsageData(
            date: today,
            totalUsageTime: totalUsageTime,
            categoryData: categoryData
        )
        
        // App Groupsに保存
        saveToAppGroups(dailyData)
        
        print("📊 カテゴリー別データ処理完了")
        print("📊 総使用時間: \(String(format: "%.1f", totalUsageTime / 60))分")
        print("📊 カテゴリー数: \(categoryData.count)")
        for category in categoryData {
            print("📊 \(category.categoryName): \(String(format: "%.1f", category.totalTime / 60))分")
        }
    }
    
    // カテゴリーの表示名を取得（Qiitaの記事を参考）
    private func getCategoryDisplayName(_ category: DeviceActivityData.CategoryActivity) -> String {
        // Try to extract a localized/display name from CategoryActivity using reflection.
        // The DeviceActivity API on some OS versions does not expose `localizedDisplayName`,
        // so avoid direct member access and fall back to "その他" when not found.
        let name = extractLocalizedName(from: category) ?? "その他"
        return getJapaneseCategoryName(from: name)
    }
    
    // Try to reflect CategoryActivity and find a String child that represents the display name.
    private func extractLocalizedName(from category: DeviceActivityData.CategoryActivity) -> String? {
        let mirror = Mirror(reflecting: category)
        for child in mirror.children {
            if let str = child.value as? String, !str.isEmpty {
                return str
            }
            // Some implementations might wrap the name in an enum or other type; try description.
            if let describable = child.value as? CustomStringConvertible {
                let desc = describable.description
                if !desc.isEmpty { return desc }
            }
        }
        // If no suitable child found, attempt a fallback representation
        let fallback = String(describing: category)
        return fallback.isEmpty ? nil : fallback
    }
    
    // Qiitaの記事から引用した変換関数
    private func getJapaneseCategoryName(from localizedName: String) -> String {
        switch localizedName {
        case "Education":
            return "教育"
        case "Social":
            return "SNS"
        case "Games":
            return "ゲーム"
        case "Entertainment":
            return "エンターテインメント"
        case "Productivity & Finance":
            return "仕事効率化とファイナンス"
        case "Creativity":
            return "クリエイティビティ"
        case "Information & Reading":
            return "情報と読書"
        case "Health & Fitness":
            return "健康とフィットネス"
        case "Shopping & Food":
            return "ショッピングとフード"
        case "Utilities":
            return "ユーティリティ"
        case "Travel":
            return "旅行"
        case "Other":
            return "その他"
        default:
            return localizedName // 不明な場合はそのまま返す
        }
    }
    
    // App Groupsにデータを保存
    private func saveToAppGroups(_ data: DailyUsageData) {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.locationreminder.app.screentime") else {
            print("❌ App GroupsのUserDefaultsにアクセスできません")
            return
        }
        
        // 既存のデータを取得
        var existingData: [DailyUsageData] = []
        if let savedData = appGroupDefaults.data(forKey: "daily_usage_data"),
           let decoded = try? JSONDecoder().decode([DailyUsageData].self, from: savedData) {
            existingData = decoded
        }
        
        // 今日のデータを更新または追加
        if let todayIndex = existingData.firstIndex(where: { 
            Calendar.current.isDate($0.date, inSameDayAs: data.date) 
        }) {
            existingData[todayIndex] = data
        } else {
            existingData.append(data)
        }
        
        // 過去30日間のデータのみ保持
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        existingData = existingData.filter { $0.date >= thirtyDaysAgo }
        
        // 保存
        if let encoded = try? JSONEncoder().encode(existingData) {
            appGroupDefaults.set(encoded, forKey: "daily_usage_data")
            print("✅ カテゴリー別データをApp Groupsに保存しました")
        } else {
            print("❌ データのエンコードに失敗しました")
        }
    }
}
