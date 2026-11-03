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
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SeatScout", targets: ["SeatScout"]),
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
        .target(name: "SeatScout", dependencies: ["CSeatScout"]),
    ]
)
