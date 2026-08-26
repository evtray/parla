// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ParlaCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ParlaCore", targets: ["ParlaCore"])
    ],
    targets: [
        .target(name: "ParlaCore"),
        .testTarget(name: "ParlaCoreTests", dependencies: ["ParlaCore"]),
    ]
)
