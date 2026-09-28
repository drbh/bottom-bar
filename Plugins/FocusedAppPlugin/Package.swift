// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusedAppPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FocusedAppPlugin", type: .dynamic, targets: ["FocusedAppPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "FocusedAppPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
