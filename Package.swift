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
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.22.0"),
    ],
    targets: [
        .executableTarget(
            name: "Akashic",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FlyingFox", package: "FlyingFox"),
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
