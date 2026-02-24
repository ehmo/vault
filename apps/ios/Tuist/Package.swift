// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "VaultDependencies",
    dependencies: [
        .package(url: "https://github.com/embrace-io/embrace-apple-sdk", from: "6.0.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/DebugSwift/DebugSwift", from: "1.11.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.0"),
    ]
)
