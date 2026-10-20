// swift-tools-version: 6.2
import PackageDescription

let usesSparkle = Context.environment["RURI_DISABLE_SPARKLE"] != "1"
let usesVex = Context.environment["RURI_ENABLE_VEX"] != "0"

var dependencies: [Package.Dependency] = [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5")
]
if usesSparkle { dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")) }
if usesVex { dependencies.append(.package(url: "https://github.com/mattt/EventSource.git", exact: "1.4.0")) }
var registrationDependencies: [Target.Dependency] = ["RuriCore", "RuriCommandKit", "RuriExtensionKit"]
if usesVex { registrationDependencies += ["RuriVex", "RuriVexUI", "RuriVexCLI"] }
var applicationDependencies: [Target.Dependency] = ["RuriCore", "RuriLocalization", "RuriExtensionKit", "RuriFeatureRegistration"]
if usesSparkle { applicationDependencies.append(.product(name: "Sparkle", package: "Sparkle")) }
var targets: [Target] = [
        .systemLibrary(name: "CZlib"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "RuriLocalization", resources: [.process("Resources")]),
        .target(name: "RuriSessionKit", dependencies: ["RuriLocalization", "CSQLite", "CZlib"]),
        .target(name: "RuriMonitorRuntime", dependencies: ["RuriSessionKit", "RuriLocalization"]),
        .target(name: "RuriCore", dependencies: ["RuriSessionKit", "ZIPFoundation", "CZlib", "CSQLite", "RuriLocalization", .product(name: "Markdown", package: "swift-markdown"), "TOMLDecoder"], resources: [.copy("Resources/LoaderSupport"), .copy("Resources/mod_data.txt")]),
        .target(name: "RuriExtensionKit", dependencies: ["RuriCore"]),
        .target(name: "RuriFeatureRegistration", dependencies: registrationDependencies, swiftSettings: usesVex ? [.define("RURI_VEX_ENABLED")] : []),
        // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
        .executableTarget(name: "Ruri", dependencies: applicationDependencies,
                          resources: [.copy("Resources/JavaBrands")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .target(name: "RuriCommandKit", dependencies: ["RuriCore", "RuriLocalization", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "RuriCLI", dependencies: ["RuriCommandKit", "RuriLocalization", "RuriFeatureRegistration"]),
        .executableTarget(name: "RuriMonitor", dependencies: ["RuriMonitorRuntime", "RuriLocalization"]),
        .testTarget(name: "RuriMonitorRuntimeTests", dependencies: ["RuriMonitorRuntime", "RuriSessionKit", "RuriLocalization"]),
        .testTarget(name: "RuriSessionKitTests", dependencies: ["RuriSessionKit"]),
        .testTarget(name: "RuriCoreTests", dependencies: ["RuriCore", "RuriMonitorRuntime", "RuriLocalization"]),
        .testTarget(name: "RuriLocalizationTests", dependencies: ["RuriLocalization"]),
        .testTarget(name: "RuriCLITests", dependencies: ["RuriCommandKit", "RuriCore"])
]
if usesVex {
    targets += [
        .target(name: "RuriVex", dependencies: ["RuriCore", "RuriLocalization", .product(name: "EventSource", package: "EventSource")], resources: [.process("Localization/Resources"), .copy("EventSource-LICENSE.txt")]),
        .target(name: "RuriVexUI", dependencies: ["RuriVex", "RuriExtensionKit", "RuriLocalization"]),
        .target(name: "RuriVexCLI", dependencies: ["RuriVex", "RuriCommandKit", "RuriLocalization", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "RuriVexTests", dependencies: ["RuriVex", "RuriCore"], resources: [.copy("VexFixtures")]),
        .testTarget(name: "RuriVexUITests", dependencies: ["RuriVexUI", "RuriVex", "RuriCore"]),
        .testTarget(name: "RuriVexCLITests", dependencies: ["RuriVexCLI", "RuriVex", "RuriFeatureRegistration", "RuriCommandKit", "RuriCore"], resources: [.copy("VexFixtures")])
    ]
}
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
    dependencies: dependencies,
    targets: targets
)
