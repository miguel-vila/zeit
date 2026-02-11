// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeitApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZeitApp", targets: ["ZeitApp"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.17.0"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "6.29.0"
        ),
        .package(
            url: "https://github.com/jpsim/Yams",
            from: "5.1.0"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ZeitApp",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ZeitApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ZeitAppTests",
            dependencies: [
                "ZeitApp",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Tests/ZeitAppTests"
        ),
    ]
)
