// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Framegentic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FramegenticKit",
            path: "Sources/FramegenticKit"
        ),
        .executableTarget(
            name: "Framegentic",
            dependencies: ["FramegenticKit"],
            path: "Sources/Framegentic"
        ),
        .testTarget(
            name: "FramegenticKitTests",
            dependencies: ["FramegenticKit"],
            path: "Tests/FramegenticKitTests"
        )
    ]
)
