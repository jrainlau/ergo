import SwiftUI

public enum ScopeStyle {
    case list
    case listWithPreview(previewRatio: CGFloat = 0.55)
    case custom(height: CGFloat, showsHostInput: Bool)
}

@MainActor
public protocol PluginScope: AnyObject {
    var title: String { get }
    var placeholder: String { get }
    var style: ScopeStyle { get }
    func items(for query: SearchQuery) async throws -> [ResultItem]
    func makeCustomView() -> AnyView
    func handleKey(_ press: KeyPress) -> Bool
    func didClose()
}

public extension PluginScope {
    func items(for query: SearchQuery) async throws -> [ResultItem] { [] }
    func makeCustomView() -> AnyView { AnyView(EmptyView()) }
    func handleKey(_ press: KeyPress) -> Bool { false }
    func didClose() {}
}
