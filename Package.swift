// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SkylightBridge",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "SkylightBridge", targets: ["SkylightBridge"])
    ],
    targets: [
        .executableTarget(
            name: "SkylightBridge",
            path: "Sources/SkylightBridge",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "SkylightBridgeTests",
            dependencies: ["SkylightBridge"],
            path: "Tests/SkylightBridgeTests",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
