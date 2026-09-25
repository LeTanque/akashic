// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Akashic",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Akashic", targets: ["Akashic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Akashic",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AkashicTests",
            dependencies: ["Akashic"]
        ),
    ]
)
