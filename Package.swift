// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BottomBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BottomBar",
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
