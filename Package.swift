// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeShot",
            path: "Sources/ClaudeShot"
        )
    ]
)
