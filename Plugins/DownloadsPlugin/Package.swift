// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DownloadsPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DownloadsPlugin", type: .dynamic, targets: ["DownloadsPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "DownloadsPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
