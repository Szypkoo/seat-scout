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
        .library(name: "SeatScoutWidget", targets: ["SeatScoutWidget"]),
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
        .target(name: "SeatScoutShared"),
        .target(name: "SeatScout", dependencies: ["CSeatScout", "SeatScoutShared"]),
        .target(name: "SeatScoutWidget", dependencies: ["SeatScoutShared"]),
    ]
)
