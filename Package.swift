// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFlow",
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
            swiftSettings: [
                // The AppKit/CoreGraphics callback surfaces here (CGEventTap,
                // AVAudioEngine taps) predate strict concurrency checking.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
