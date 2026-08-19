// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let helperInfoPlist = "\(packageDirectory)/Resources/PhotoKitHelper-Info.plist"

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
            dependencies: ["PhotoKitProtocol"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", helperInfoPlist,
                ]),
            ]
        ),
        .testTarget(
            name: "PhotoKitProtocolTests",
            dependencies: ["PhotoKitProtocol"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
