// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "NextcloudContainerManager",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "NextcloudContainerManager",
            targets: ["NextcloudContainerManager"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
    ],
    targets: [
        .target(
            name: "NextcloudContainerManager"
        ),
        .executableTarget(
            name: "Runner",
            dependencies: ["NextcloudContainerManager"]
        ),
    ]
)
