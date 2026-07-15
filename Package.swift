// swift-tools-version: 5.7
// Conferbot iOS SDK package manifest.
// CI on Linux swaps this for Package.linux.swift (see test-infra/Dockerfile.ios),
// which stubs SocketIO/Combine and excludes UIKit/SwiftUI sources.

import PackageDescription

let package = Package(
    name: "Conferbot",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Conferbot",
            targets: ["Conferbot"])
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", .upToNextMajor(from: "16.0.0"))
    ],
    targets: [
        .target(
            name: "Conferbot",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ],
            path: "Sources/Conferbot"
        ),
        .testTarget(
            name: "ConferbotTests",
            dependencies: ["Conferbot"],
            path: "Tests",
            exclude: [
                "ConnectionTest.swift"
            ]
        )
    ]
)
