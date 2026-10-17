// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UniFiBar",
    // The deployment target stays macOS 26 so Tahoe users keep working. The sources
    // also compile and pass tests against the macOS 27 SDK with Xcode 27.
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
