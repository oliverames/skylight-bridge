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
            from: "0.1.9"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.9.4"
        )
    ],
    targets: [
        .executableTarget(
            name: "SkylightBridge",
            dependencies: [
                .product(name: "SkylightBridgeShared", package: "skylight-bridge-ios"),
                .product(name: "Sparkle", package: "Sparkle")
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
