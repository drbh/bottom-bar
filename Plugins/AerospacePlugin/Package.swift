// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AerospacePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AerospacePlugin", type: .dynamic, targets: ["AerospacePlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "AerospacePlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
