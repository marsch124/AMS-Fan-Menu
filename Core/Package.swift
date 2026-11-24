// swift-tools-version:5.9
import PackageDescription

// The rules of AMS Fan Menu that need no fan hardware, so they can be tested in seconds.
let package = Package(
    name: "FanMenuCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FanMenuCore", targets: ["FanMenuCore"])],
    targets: [
        .target(name: "FanMenuCore"),
        .testTarget(name: "FanMenuCoreTests", dependencies: ["FanMenuCore"]),
    ]
)
