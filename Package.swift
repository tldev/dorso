// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dorso",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DorsoCore", targets: ["DorsoCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.10.0")
    ],
    targets: [
        // Core logic library - testable, no main entry point
        .target(
            name: "DorsoCore",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            path: "Sources",
            exclude: ["App", "Icons"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("IOBluetooth")
            ]
        ),
        // Executable target
        .executableTarget(
            name: "Dorso",
            dependencies: ["DorsoCore"],
            path: "Sources/App"
        ),
        // Test target
        .testTarget(
            name: "DorsoTests",
            dependencies: [
                "DorsoCore",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            path: "Tests"
        )
    ]
)
