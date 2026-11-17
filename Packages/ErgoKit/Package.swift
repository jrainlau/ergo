// swift-tools-version: 6.2
import PackageDescription

let common: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let kit: Target.Dependency = "ErgoPluginKit"
let support: Target.Dependency = "ErgoPluginSupport"
let ui: Target.Dependency = "ErgoUI"
let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")
let shortcuts: Target.Dependency = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
let markdown: Target.Dependency = .product(name: "MarkdownUI", package: "swift-markdown-ui")

func plugin(_ name: String, extra: [Target.Dependency] = []) -> Target {
    .target(name: name, dependencies: [kit, support, ui] + extra, swiftSettings: common)
}

func tests(_ name: String, _ deps: [Target.Dependency]) -> Target {
    .testTarget(name: name, dependencies: deps, swiftSettings: common)
}

let package = Package(
    name: "ErgoKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ErgoAppCore", targets: ["ErgoAppCore"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .target(name: "ErgoPluginKit", swiftSettings: common),
        .target(name: "ErgoPluginSupport", dependencies: [kit], swiftSettings: common),
        .target(name: "ErgoUI", dependencies: [kit, support], swiftSettings: common),
        .target(name: "ErgoCore", dependencies: [kit, support, ui, grdb, shortcuts], swiftSettings: common),
        .target(name: "ErgoLauncher", dependencies: [kit, support, ui, "ErgoCore", shortcuts], swiftSettings: common),
        .target(name: "ErgoSettings", dependencies: [kit, support, ui, "ErgoCore", shortcuts], swiftSettings: common),

        plugin("PluginCalculator"),
        plugin("PluginAppLauncher"),
        plugin("PluginFileSearch"),
        plugin("PluginClipboard", extra: [grdb]),
        plugin("PluginCurrency"),
        plugin("PluginSnippets", extra: [grdb]),
        plugin("PluginAIChat", extra: [grdb, markdown]),

        .target(
            name: "ErgoAppCore",
            dependencies: [
                kit, support, ui, "ErgoCore", "ErgoLauncher", "ErgoSettings", shortcuts,
                "PluginCalculator", "PluginAppLauncher", "PluginFileSearch", "PluginClipboard",
                "PluginCurrency", "PluginSnippets", "PluginAIChat",
            ],
            swiftSettings: common
        ),

        tests("ErgoPluginSupportTests", ["ErgoPluginSupport", kit]),
        tests("ErgoCoreTests", ["ErgoCore", kit, support]),
        tests("ErgoLauncherTests", ["ErgoLauncher", "ErgoCore", kit]),
        tests("PluginCalculatorTests", ["PluginCalculator", kit, support]),
        tests("PluginCurrencyTests", ["PluginCurrency", kit, support]),
        tests("PluginClipboardTests", ["PluginClipboard", kit, support]),
        tests("PluginAIChatTests", ["PluginAIChat", kit, support]),
        tests("PluginAppLauncherTests", ["PluginAppLauncher", kit, support]),
        tests("PluginSnippetsTests", ["PluginSnippets", kit, support]),
    ]
)
