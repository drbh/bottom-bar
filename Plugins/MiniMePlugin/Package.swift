// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniMePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MiniMePlugin", type: .dynamic, targets: ["MiniMePlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "MiniMePlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
