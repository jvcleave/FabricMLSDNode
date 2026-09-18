// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLSDStructuralLineKit",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "MLSDStructuralLineKit", targets: ["MLSDStructuralLineKit"]),
    ],
    targets: [
        .target(
            name: "MLSDStructuralLineKit",
            resources: [
                .copy("Compute"),
                .copy("Models"),
            ]
        ),
        .testTarget(
            name: "MLSDStructuralLineKitTests",
            dependencies: ["MLSDStructuralLineKit"]
        ),
    ]
)
