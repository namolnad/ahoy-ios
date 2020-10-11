// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Ahoy",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "Ahoy",
            targets: ["Ahoy"]
        ),
    ],
    targets: [
        .target(
            name: "Ahoy",
            dependencies: []),
        .testTarget(
            name: "AhoyTests",
            dependencies: ["Ahoy"]),
    ]
)
