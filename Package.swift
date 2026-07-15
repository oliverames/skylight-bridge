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
    dependencies: [
        .package(
            url: "https://github.com/oliverames/skylight-bridge-ios.git",
            from: "0.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "SkylightBridge",
            dependencies: [
                .product(name: "SkylightBridgeShared", package: "skylight-bridge-ios")
            ],
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
