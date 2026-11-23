// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FleetPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FleetPlugin", type: .dynamic, targets: ["FleetPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "FleetPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
