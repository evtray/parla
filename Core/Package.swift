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
        // `make eval-capture`: manda las capturas de muestra a la API real. Gasta
        // tokens, por eso no es un test.
        .executableTarget(name: "parla-eval", dependencies: ["ParlaCore"]),
        .testTarget(name: "ParlaCoreTests", dependencies: ["ParlaCore"]),
    ]
)
