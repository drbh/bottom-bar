// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClockPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClockPlugin", type: .dynamic, targets: ["ClockPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "ClockPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
