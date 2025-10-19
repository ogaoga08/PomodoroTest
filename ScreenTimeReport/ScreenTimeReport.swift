//
//  ScreenTimeReport.swift
//  ScreenTimeReport
//
//  Created by 小笠原慎 on 2025/10/17.
//

import DeviceActivity
import ExtensionKit
import SwiftUI

// ExtentionTarget.swift
@main
@MainActor
struct report_test: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // 棒グラフ表示用レポート
        TotalActivityReport(context: .barGraph) { totalActivity in
            TotalActivityView(contextLabel: "barGraph")
        }

        // 円グラフ表示用レポート
        TotalActivityReport(context: .pieChart) { totalActivity in
            TotalActivityView(contextLabel: "pieChart")
        }
        
        // カテゴリー別データ処理用レポート
        TotalActivityReport(context: .categoryData) { categoryData in
            TotalActivityView(contextLabel: "categoryData")
        }
    }
}
