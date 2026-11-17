import ErgoPluginKit
import PluginAppLauncher
import PluginCalculator
import PluginClipboard
import PluginCurrency
import PluginFileSearch
import PluginSnippets

/// 所有内置插件。新增插件只需在这里加一行。
@MainActor
enum PluginCatalog {
    static let all: [any ErgoPlugin.Type] = [
        CalculatorPlugin.self,
        AppLauncherPlugin.self,
        FileSearchPlugin.self,
        CurrencyPlugin.self,
        ClipboardPlugin.self,
        SnippetsPlugin.self,
    ]
}
