import ErgoPluginKit
import PluginCalculator

/// 所有内置插件。新增插件只需在这里加一行。
@MainActor
enum PluginCatalog {
    static let all: [any ErgoPlugin.Type] = [
        CalculatorPlugin.self,
    ]
}
