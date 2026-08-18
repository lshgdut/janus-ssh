// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JanusSSHTunnelEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "JanusSSHTunnelEngine",
            targets: ["JanusSSHTunnelEngine"]
        )
    ],
    targets: [
        .target(
            name: "JanusSSHTunnelEngine",
            path: "Sources/JanusSSHTunnelEngine"
        ),
        .testTarget(
            name: "JanusSSHTunnelEngineTests",
            dependencies: ["JanusSSHTunnelEngine"],
            path: "Tests/JanusSSHTunnelEngineTests"
        )
    ]
)