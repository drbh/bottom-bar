// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HelloPlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "HelloPlugin",
            type: .dynamic,
            targets: ["HelloPlugin"]
        )
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .target(
            name: "HelloPlugin",
            dependencies: [
                .product(name: "BottomBarSDK", package: "bottom-bar")
            ],
            path: "Sources/HelloPlugin",
            exclude: ["Info.plist"]
        )
    ]
)
