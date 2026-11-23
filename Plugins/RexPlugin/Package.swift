// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RexPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RexPlugin", type: .dynamic, targets: ["RexPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "RexPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
