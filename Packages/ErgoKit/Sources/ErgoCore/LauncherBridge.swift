import Foundation
import ErgoPluginKit

/// Core 与 Launcher 之间的桥：Launcher 在创建后填入回调。
public final class LauncherBridge: LauncherControlling {
    public var visibleProvider: () -> Bool = { false }
    public var onShow: (PluginID?, String?) -> Void = { _, _ in }
    public var onHide: () -> Void = {}
    public var onSetQuery: (String) -> Void = { _ in }
    public var onRefresh: () -> Void = {}

    public init() {}

    public var isVisible: Bool { visibleProvider() }
    public func show(scope: PluginID?, query: String?) { onShow(scope, query) }
    public func hide() { onHide() }
    public func setQuery(_ text: String) { onSetQuery(text) }
    public func refresh() { onRefresh() }
}
