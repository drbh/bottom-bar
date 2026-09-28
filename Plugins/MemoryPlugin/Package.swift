// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoryPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MemoryPlugin", type: .dynamic, targets: ["MemoryPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "MemoryPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
