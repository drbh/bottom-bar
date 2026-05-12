// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectsPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProjectsPlugin", type: .dynamic, targets: ["ProjectsPlugin"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "ProjectsPlugin",
            dependencies: [.product(name: "BottomBarSDK", package: "bottom-bar")],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
