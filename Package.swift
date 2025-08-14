// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cw",
    products: [
        .library(
            name: "cw",
            targets: ["cw"]),
        .executable(
            name: "listen",
            targets: ["listen"]
        )
    ],
    targets: [
        .target(
            name: "cw"),
        .executableTarget(
            name: "listen",
            dependencies: [
                .target(name: "cw")
            ]
        ),
        .testTarget(
            name: "cwTests",
            dependencies: ["cw"],
            resources: [
                .copy("./samples")
            ]
        ),
    ]
)
