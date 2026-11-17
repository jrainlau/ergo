import SwiftUI

@MainActor
public protocol ErgoPlugin: AnyObject {
    static var manifest: PluginManifest { get }
    init()
    func activate(context: any PluginContext) async throws
    func deactivate() async
    var searchProvider: (any SearchProvider)? { get }
    func makeScope() -> (any PluginScope)?
    func perform(hotkey: HotkeyActionID) async
    func makeSettingsView() -> AnyView?
    func makeManagementView() -> AnyView?
}

public extension ErgoPlugin {
    func deactivate() async {}
    var searchProvider: (any SearchProvider)? { nil }
    func makeScope() -> (any PluginScope)? { nil }
    func perform(hotkey: HotkeyActionID) async {}
    func makeSettingsView() -> AnyView? { nil }
    func makeManagementView() -> AnyView? { nil }
}
