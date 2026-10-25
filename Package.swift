// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MurmurKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
        .library(name: "MurmurUI", targets: ["MurmurUI"]),
    ],
    targets: [
        // Logic only. No UI imports.
        .target(name: "MurmurCore"),
        // Theme, motion and shared SwiftUI components used by every platform target.
        .target(name: "MurmurUI", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurUITests", dependencies: ["MurmurUI"]),
    ],
    swiftLanguageModes: [.v5]
)
