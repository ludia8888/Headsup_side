// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JiminCore",
    platforms: [.iOS("17.4"), .macOS(.v13)],
    products: [.library(name: "JiminCore", targets: ["JiminCore"])],
    targets: [
        .target(name: "JiminCore"),
        .testTarget(name: "JiminCoreTests", dependencies: ["JiminCore"])
    ]
)
