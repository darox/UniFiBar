// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UniFiBar",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "UniFiBar",
            path: "Sources/UniFiBar",
            resources: [
                .copy("../../Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "UniFiBarTests",
            dependencies: ["UniFiBar"],
            path: "Tests/UniFiBarTests"
        )
    ]
)
