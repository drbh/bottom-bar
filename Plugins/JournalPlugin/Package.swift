// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JournalPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JournalPlugin", type: .dynamic, targets: ["JournalPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "JournalPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
