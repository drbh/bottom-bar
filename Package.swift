// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BottomBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "BottomBarSDK",
            type: .dynamic,
            targets: ["BottomBarSDK"]
        )
    ],
    targets: [
        .target(
            name: "BottomBarSDK",
            path: "Sources/BottomBarSDK"
        ),
        .executableTarget(
            name: "BottomBar",
            dependencies: ["BottomBarSDK"],
            path: "Sources/BottomBar",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/BottomBar/Info.plist",
                ])
            ]
        )
    ]
)
