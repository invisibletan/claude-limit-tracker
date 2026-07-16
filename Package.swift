// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "UsageCore",
            path: "Sources/UsageCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudeUsageTracker",
            dependencies: ["UsageCore"],
            path: "Sources/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
