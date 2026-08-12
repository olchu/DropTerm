// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DropTerm",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DropTerm", targets: ["DropTerm"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "DropTerm",
            dependencies: ["SwiftTerm"],
            path: "Sources/DropTerm"
        ),
        .testTarget(
            name: "DropTermTests",
            dependencies: ["DropTerm"],
            path: "Tests/DropTermTests"
        )
    ]
)
