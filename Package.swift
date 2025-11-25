// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.0.0")
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
            path: "Tests"
        )
    ]
)
