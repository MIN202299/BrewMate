// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrewMate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BrewMate",
            path: "Sources/BrewMate",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
