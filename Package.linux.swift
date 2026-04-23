// swift-tools-version: 5.7
// Linux-compatible Package.swift for CI/syntax checking
// Uses local SocketIO shim since GitHub is unreachable in this environment

import PackageDescription

let package = Package(
    name: "Conferbot",
    products: [
        .library(
            name: "Conferbot",
            targets: ["Conferbot"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SocketIO",
            path: "SocketIO"
        ),
        .target(
            name: "Combine",
            path: "CombineShim"
        ),
        .target(
            name: "Conferbot",
            dependencies: ["SocketIO", "Combine"],
            path: "Sources/Conferbot",
            exclude: [
                "UI/SwiftUI",
                "UI/UIKit",
                "Services/OfflineManager.swift",
                "Services/KnowledgeBaseService.swift",
                "Services/FileUploadService.swift",
                "Services/APIClient.swift",
                "Utils/ValidationUtils.swift",
                "Core/ConferBot.swift",
                "Analytics/ChatAnalytics.swift"
            ]
        )
    ]
)
