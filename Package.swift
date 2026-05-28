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
    targets: [
        .executableTarget(
            name: "VoiceInk",
            path: "VoiceInk"
        )
    ]
)
