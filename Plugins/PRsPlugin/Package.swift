// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRsPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PRsPlugin", type: .dynamic, targets: ["PRsPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "PRsPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
