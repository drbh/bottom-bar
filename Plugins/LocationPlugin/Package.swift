// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocationPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LocationPlugin", type: .dynamic, targets: ["LocationPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "LocationPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
