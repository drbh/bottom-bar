// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StocksPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StocksPlugin", type: .dynamic, targets: ["StocksPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "StocksPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
