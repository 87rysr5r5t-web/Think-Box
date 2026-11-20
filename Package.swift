// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThinkBox",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ThinkBox", targets: ["ThinkBox"])],
    targets: [
        .target(name: "WritingLibrary"),
        .executableTarget(name: "ThinkBox", dependencies: ["WritingLibrary"], resources: [.copy("Fonts")]),
        .testTarget(name: "WritingLibraryTests", dependencies: ["WritingLibrary"]),
    ]
)
