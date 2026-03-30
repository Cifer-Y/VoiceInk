// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VoiceInk",
            targets: ["VoiceInk"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/whisper.spm.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceInk",
            dependencies: [
                .product(name: "whisper", package: "whisper.spm"),
            ],
            path: "VoiceInk"
        )
    ]
)
