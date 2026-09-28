// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DiskPlugin", type: .dynamic, targets: ["DiskPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "DiskPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
