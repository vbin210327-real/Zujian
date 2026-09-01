// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZujianDetection",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DetectionCore", targets: ["DetectionCore"])
    ],
    targets: [
        .target(
            name: "DetectionCore",
            path: "Zujian",
            exclude: [
                "App",
                "Managers",
                "Resources",
                "Views",
                "Models/ZujianWidgetSnapshot.swift"
            ],
            sources: [
                "Detection",
                "Models/WorkoutModels.swift"
            ]
        ),
        .testTarget(
            name: "DetectionCoreTests",
            dependencies: ["DetectionCore"],
            path: "ZujianTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
