// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UptimePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "UptimePlugin", type: .dynamic, targets: ["UptimePlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "UptimePlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
