// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SushiBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SushiBuddy", path: "Sources/SushiBuddy"),
        .testTarget(name: "SushiBuddyTests", dependencies: ["SushiBuddy"], path: "Tests/SushiBuddyTests"),
    ]
)
