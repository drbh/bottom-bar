// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CpuPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CpuPlugin", type: .dynamic, targets: ["CpuPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "CpuPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
