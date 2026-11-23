// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsagePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexUsagePlugin", type: .dynamic, targets: ["CodexUsagePlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "CodexUsagePlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
