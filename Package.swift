// swift-tools-version: 6.2
import PackageDescription

// Package managers that update the app themselves (such as Nix) set
// RURI_DISABLE_SPARKLE=1 to build without Sparkle's in-app updater.
let usesSparkle = Context.environment["RURI_DISABLE_SPARKLE"] != "1"

let package = Package(
    name: "Ruri",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ruri", targets: ["Ruri"]),
        .executable(name: "ruri-cli", targets: ["RuriCLI"]),
        .executable(name: "ruri-monitor", targets: ["RuriMonitor"]),
        .library(name: "RuriCore", targets: ["RuriCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5")
    ] + (usesSparkle ? [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")] : []),
    targets: [
        .systemLibrary(name: "CZlib"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "RuriLocalization", resources: [.process("Resources")]),
        .target(name: "RuriSessionKit", dependencies: ["RuriLocalization", "CSQLite", "CZlib"]),
        .target(name: "RuriMonitorRuntime", dependencies: ["RuriSessionKit", "RuriLocalization"]),
        .target(name: "RuriCore", dependencies: ["RuriSessionKit", "ZIPFoundation", "CZlib", "CSQLite", "RuriLocalization", .product(name: "Markdown", package: "swift-markdown"), "TOMLDecoder"], resources: [.copy("Resources/LoaderSupport"), .copy("Resources/mod_data.txt")]),
        // Extension points; see docs/extensions.md.
        .target(name: "RuriExtensionKit", dependencies: ["RuriCore"]),
        .target(name: "RuriFeatureRegistration", dependencies: ["RuriCore", "RuriCommandKit", "RuriExtensionKit"]),
        // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
        .executableTarget(name: "Ruri", dependencies: ["RuriCore", "RuriLocalization", "RuriExtensionKit", "RuriFeatureRegistration"] + (usesSparkle ? [.product(name: "Sparkle", package: "Sparkle")] : []),
                          resources: [.copy("Resources/JavaBrands")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .target(name: "RuriCommandKit", dependencies: ["RuriCore", "RuriLocalization", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "RuriCLI", dependencies: ["RuriCommandKit", "RuriLocalization", "RuriFeatureRegistration"]),
        .executableTarget(name: "RuriMonitor", dependencies: ["RuriMonitorRuntime", "RuriLocalization"]),
        .testTarget(name: "RuriMonitorRuntimeTests", dependencies: ["RuriMonitorRuntime", "RuriSessionKit", "RuriLocalization"]),
        .testTarget(name: "RuriSessionKitTests", dependencies: ["RuriSessionKit"]),
        .testTarget(name: "RuriCoreTests", dependencies: ["RuriCore", "RuriMonitorRuntime", "RuriLocalization"]),
        .testTarget(name: "RuriLocalizationTests", dependencies: ["RuriLocalization"]),
        .testTarget(name: "RuriCLITests", dependencies: ["RuriCommandKit", "RuriCore"]),
        // A sample extension that uses every extension point; it exists only here.
        .testTarget(name: "RuriExtensionTests", dependencies: ["RuriCore", "RuriCommandKit", "RuriExtensionKit", "RuriFeatureRegistration",
                                                              .product(name: "ArgumentParser", package: "swift-argument-parser")])
    ]
)
