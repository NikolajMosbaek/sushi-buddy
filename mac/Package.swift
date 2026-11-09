// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SushiBuddy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "SushiBuddy",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SushiBuddy"
        ),
        .testTarget(name: "SushiBuddyTests", dependencies: ["SushiBuddy"], path: "Tests/SushiBuddyTests"),
    ]
)
