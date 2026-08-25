// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFlow",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        // WhisperKit: OpenAI Whisper models compiled to Core ML, so transcription
        // runs on the Neural Engine. The repo was renamed from argmaxinc/WhisperKit.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "OpenFlow",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/OpenFlow",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                // The AppKit/CoreGraphics callback surfaces here (CGEventTap,
                // AVAudioEngine taps) predate strict concurrency checking.
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "OpenFlowTests",
            dependencies: ["OpenFlow"],
            path: "Tests/OpenFlowTests"
        ),
    ]
)
