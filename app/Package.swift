// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LazyWebp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LazyWebp",
            path: "Sources/LazyWebp"
        )
    ]
)
