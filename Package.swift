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
            exclude: [
                "overall_style_flat_2d_icon_style_minimalist_vector_019c9eb7-e897-7717-9394-4a0e4a674fb8.svg"
            ],
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
