// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StarlinkKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StarlinkKit", targets: ["StarlinkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.39.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf", from: "2.5.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport", from: "2.9.0"),
    ],
    targets: [
        // Generated from reference/router.protoset (see Scripts/generate-protos.sh).
        .target(
            name: "RouterAPI",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Generated from reference/dish.protoset.
        .target(
            name: "DishAPI",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "StarlinkKit",
            dependencies: [
                "RouterAPI", "DishAPI",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
            ],
            resources: [.copy("Resources/Fixtures"), .copy("Resources/Geo"), .copy("Resources/Orbits")]
        ),
        .executableTarget(name: "perigee-probe", dependencies: ["StarlinkKit"]),
        .testTarget(name: "StarlinkKitTests", dependencies: ["StarlinkKit"]),
    ]
)
