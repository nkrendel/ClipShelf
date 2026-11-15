// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipShelf",
            path: "Sources/ClipShelf",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "ClipShelfTests",
            dependencies: ["ClipShelf"],
            path: "Tests/ClipShelfTests"
        ),
    ]
)
