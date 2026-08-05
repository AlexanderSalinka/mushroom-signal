// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MushroomSignalCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MushroomSignalCore", targets: ["MushroomSignalCore"])
    ],
    targets: [
        .target(name: "MushroomSignalCore"),
        .testTarget(
            name: "MushroomSignalCoreTests",
            dependencies: ["MushroomSignalCore"]
        )
    ]
)
