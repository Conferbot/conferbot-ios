// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "ConferbotExample",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ConferbotExample",
            dependencies: [
                .product(name: "Conferbot", package: "conferbot-ios")
            ],
            path: "Sources"
        )
    ]
)
