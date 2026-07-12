// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodcastTranscriptStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PodcastTranscriptStudio", targets: ["PodcastTranscriptStudio"])
    ],
    targets: [
        .executableTarget(
            name: "PodcastTranscriptStudio",
            path: "Sources/PodcastTranscriptStudio",
            resources: [
                .copy("Resources/DefaultPrompts")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "PodcastTranscriptStudioTests",
            dependencies: ["PodcastTranscriptStudio"],
            path: "Tests/PodcastTranscriptStudioTests"
        )
    ]
)
