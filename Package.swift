// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Ahoy",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS("6.2")
    ],
    products: [
        .library(name: "Ahoy", targets: ["Ahoy"]),
    ],
    targets: [
        .target(name: "Ahoy", dependencies: []),
        .testTarget(name: "AhoyTests", dependencies: ["Ahoy"]),
    ]
)
