// swift-tools-version: 6.0
import Foundation
import PackageDescription

let coreLibraryPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("core/dist/ios")
    .path

let package = Package(
    name: "SeatScout",
    defaultLocalization: "pl",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SeatScoutApp", type: .dynamic, targets: ["SeatScout"]),
        .library(name: "SeatScout", targets: ["SeatScout"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.1.0"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.1.0"),
        .package(url: "https://source.skip.tools/skip-model.git", from: "1.1.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "CSeatScout",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L", coreLibraryPath]),
                .linkedLibrary("seat_scout_core"),
            ]
        ),
        .target(
            name: "SeatScout",
            dependencies: [
                "CSeatScout",
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipModel", package: "skip-model"),
                .product(name: "SkipFoundation", package: "skip-foundation"),
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip"),
            ]
        ),
    ]
)
