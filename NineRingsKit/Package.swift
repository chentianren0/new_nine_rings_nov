// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NineRingsKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Puzzle", targets: ["Puzzle"]),
        .library(name: "Toy", targets: ["Toy"]),
    ],
    targets: [
        .target(
            name: "Puzzle",
            swiftSettings: [.strictMemorySafety()]
        ),
        .target(
            name: "Toy",
            dependencies: ["Puzzle"],
            resources: [.process("Resources")],
            swiftSettings: [.strictMemorySafety()]
        ),
        .testTarget(name: "PuzzleTests", dependencies: ["Puzzle"]),
        .testTarget(name: "ToyTests", dependencies: ["Toy"]),
    ]
)
