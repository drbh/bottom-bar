// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NetworkPlugin", type: .dynamic, targets: ["NetworkPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "NetworkPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
