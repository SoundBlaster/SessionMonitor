// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionMonitor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "codex-monitor", targets: ["MonitorCLI"]),
        .library(name: "MonitorRuntime", targets: ["MonitorRuntime"]),
        .library(name: "MonitorCore", targets: ["MonitorCore"]),
        .library(name: "MonitorPolicies", targets: ["MonitorPolicies"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/SoundBlaster/SpecificationCore", exact: "1.1.0"),
        // Linux only: CryptoKit's API from Apple's open-source swift-crypto. macOS keeps system CryptoKit.
        .package(url: "https://github.com/apple/swift-crypto", exact: "3.15.1")
    ],
    targets: [
        .target(name: "MonitorCore"),
        .target(name: "MonitorPolicies", dependencies: [
            "MonitorCore", .product(name: "SpecificationCore", package: "SpecificationCore")
        ]),
        .target(name: "CodexSource", dependencies: [
            "MonitorCore", .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
        ]),
        .target(name: "MonitorStore", dependencies: [
            "MonitorCore", "MonitorPolicies", .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
        ]),
        .target(name: "MonitorRuntime", dependencies: [
            "MonitorCore", "MonitorPolicies", "CodexSource", "MonitorStore"
        ]),
        .executableTarget(name: "MonitorCLI", dependencies: [
            "MonitorRuntime", .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .testTarget(name: "SessionMonitorTests", dependencies: [
            "MonitorCore", "MonitorPolicies", "CodexSource", "MonitorStore", "MonitorRuntime",
            .product(name: "SpecificationCore", package: "SpecificationCore")
        ])
    ]
)
