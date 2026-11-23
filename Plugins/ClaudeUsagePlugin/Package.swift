// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClaudeUsagePlugin", type: .dynamic, targets: ["ClaudeUsagePlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "ClaudeUsagePlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
