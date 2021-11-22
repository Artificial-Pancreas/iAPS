// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LibreTransmitter",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "LibreTransmitter",
            targets: ["LibreTransmitter"]),
        .library(
            name: "RawGlucose",
            targets: ["RawGlucose"]),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "RawGlucose",
            path: "RawGlucose.xcframework"),
        .target(
            name: "LibreTransmitter",
            dependencies: ["RawGlucose"],
            resources: [.process("LibreTransmitterUI/Graphics")]
        )

    ]
)
