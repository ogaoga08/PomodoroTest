// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroReminderApp",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PomodoroReminderApp",
            targets: ["PomodoroReminderApp"])
    ],
    targets: [
        .target(
            name: "PomodoroReminderApp",
            dependencies: []),
        .testTarget(
            name: "PomodoroReminderAppTests",
            dependencies: ["PomodoroReminderApp"])
    ]
) 