// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "PelotonDeskASR",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])],
    targets: [.executableTarget(name: "PelotonDeskASR", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")], path: "Sources")]
)
