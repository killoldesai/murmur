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
        // WhisperKit engine. Separate so the Watch target can use MurmurCore without it.
        .library(name: "MurmurWhisper", targets: ["MurmurWhisper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        // Logic only. No UI imports.
        .target(name: "MurmurCore"),
        // Theme, motion and shared SwiftUI components used by every platform target.
        .target(name: "MurmurUI", dependencies: ["MurmurCore"]),
        .target(
            name: "MurmurWhisper",
            dependencies: [
                "MurmurCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurUITests", dependencies: ["MurmurUI"]),
        .testTarget(name: "MurmurWhisperTests", dependencies: ["MurmurWhisper", "MurmurCore"]),
    ],
    swiftLanguageModes: [.v5]
)
