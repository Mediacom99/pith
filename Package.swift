// swift-tools-version: 6.4
import PackageDescription

// "Approachable concurrency": nonisolated async functions run on the caller's actor, and conformances
// inherit the isolation of the type they're declared on.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Launcher",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Launcher", targets: ["Launcher"])
    ],
    targets: [
        // Pure logic: app scanning, the in-memory index, fuzzy matching, FSEvents. No AppKit.
        .target(name: "LauncherCore", swiftSettings: concurrency),
        // The AppKit app: panel, hotkey, views. Main actor unless stated otherwise.
        .executableTarget(
            name: "Launcher",
            dependencies: ["LauncherCore"],
            swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"], swiftSettings: concurrency),
    ]
)
