// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KidsWordDictation",
    platforms: [
        .iOS("18.0"),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "KidsWordDictationCore",
            targets: ["KidsWordDictationCore"]
        )
    ],
    targets: [
        .target(
            name: "KidsWordDictationCore",
            path: "SharedCore"
        ),
        .testTarget(
            name: "KidsWordDictationCoreTests",
            dependencies: ["KidsWordDictationCore"],
            path: "KidsWordDictationCoreTests"
        )
    ]
)
