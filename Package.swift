// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeShotKit",
            path: "Sources/ClaudeShotKit"
        ),
        .executableTarget(
            name: "ClaudeShot",
            dependencies: ["ClaudeShotKit"],
            path: "Sources/ClaudeShot"
        ),
        .testTarget(
            name: "ClaudeShotKitTests",
            dependencies: ["ClaudeShotKit"],
            path: "Tests/ClaudeShotKitTests"
        )
    ]
)
