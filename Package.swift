// swift-tools-version: 6.4
import PackageDescription

// "Approachable concurrency": nonisolated async functions run on the caller's actor, and conformances
// inherit the isolation of the type they're declared on.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Pith",
    platforms: [.macOS(.v26)],
    products: [
        // The app is Pith (decision 30); its modules keep the names of what they are: a launcher.
        .executable(name: "Pith", targets: ["Launcher"])
    ],
    dependencies: [
        // Updates (decision 48): the one third-party dependency. Pinned; `make app` embeds and signs its framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        // Pure logic: app scanning, the in-memory index, fuzzy matching, FSEvents. No AppKit.
        .target(name: "LauncherCore", swiftSettings: concurrency),
        // The AppKit app: panel, hotkey, views. Main actor unless stated otherwise.
        .executableTarget(
            name: "Launcher",
            dependencies: ["LauncherCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]
        ),
        // Helpers shared by the test targets: temporary folders on the real file system.
        .target(name: "TestSupport", path: "Tests/TestSupport", swiftSettings: concurrency),
        .testTarget(
            name: "LauncherCoreTests", dependencies: ["LauncherCore", "TestSupport"], swiftSettings: concurrency),
        // AppKit layout and drawing, in panels that are never put on screen.
        .testTarget(
            name: "LauncherTests",
            dependencies: ["Launcher", "TestSupport"],
            swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]
        ),
    ]
)
