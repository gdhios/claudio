// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Plume",
            dependencies: ["KeyboardShortcuts"]
        )
    ]
)
