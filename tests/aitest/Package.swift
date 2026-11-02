// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aitest",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/mattt/llama.swift", exact: "2.10549.0")],
    targets: [.executableTarget(
        name: "aitest",
        dependencies: [.product(name: "LlamaSwift", package: "llama.swift")],
        path: "Sources/aitest",
        swiftSettings: [.swiftLanguageMode(.v5)]
    )]
)
