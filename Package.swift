// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacMetricsView",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacMetricsView", targets: ["MacMetricsView"])
    ],
    targets: [
        .executableTarget(
            name: "MacMetricsView",
            path: "MacMetricsView",
            exclude: ["Info.plist", "SwiftPMInfo.plist", "Assets.xcassets"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "MacMetricsView/SwiftPMInfo.plist"
                ])
            ]
        ),
        .testTarget(
            name: "MacMetricsViewTests",
            dependencies: ["MacMetricsView"],
            path: "MacMetricsViewTests",
            // Loaded by GeminiCLILogReaderTests via #filePath, not as SPM resources.
            exclude: ["Fixtures"]
        )
    ]
)
