// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DropTerm",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DropTerm", targets: ["DropTerm"])
    ],
    targets: [
        .executableTarget(
            name: "DropTerm",
            path: "Sources/DropTerm"
        ),
        .testTarget(
            name: "DropTermTests",
            dependencies: ["DropTerm"],
            path: "Tests/DropTermTests"
        )
    ]
)

