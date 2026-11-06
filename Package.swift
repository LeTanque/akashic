// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Akashic",
    platforms: [
        .macOS("15.0"),
        .iOS("17.0"),
    ],
    products: [
        .executable(name: "Akashic", targets: ["Akashic"]),
        .library(name: "AkashicCore", targets: ["AkashicCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.22.0"),
    ],
    targets: [
        .target(
            name: "AkashicCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Akashic",
            dependencies: [
                "AkashicCore",
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "AkashicTests",
            dependencies: ["Akashic", "AkashicCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
