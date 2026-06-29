// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "harness-app",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HarnessApp",
            path: "Sources/HarnessApp"
        )
    ]
)