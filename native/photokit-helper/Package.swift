// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "photokit-helper",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "photokit-helper", targets: ["PhotoKitHelper"]),
    ],
    targets: [
        .target(name: "PhotoKitProtocol"),
        .executableTarget(
            name: "PhotoKitHelper",
            dependencies: ["PhotoKitProtocol"]
        ),
        .testTarget(
            name: "PhotoKitProtocolTests",
            dependencies: ["PhotoKitProtocol"]
        ),
    ]
)
