// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MousePortal",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MousePortal",
            path: "MousePortal",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MousePortalTests",
            dependencies: ["MousePortal"],
            path: "MousePortalTests"
        )
    ]
)
