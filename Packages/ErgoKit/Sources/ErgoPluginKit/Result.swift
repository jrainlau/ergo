import AppKit
import SwiftUI

public enum ResultIcon {
    case symbol(String)
    case fileIcon(URL)
    case appIcon(URL)
    case image(NSImage)
    case bundleAppIcon(bundleID: String)
}

public enum ActionOutcome {
    case hideLauncher
    case keepOpen
    case setQuery(String)
    case refresh
    case openScope(PluginID)
}

@MainActor
public struct ResultAction: Identifiable {
    public var id: String
    public var title: String
    public var shortcut: KeyStroke?
    public var perform: () async -> ActionOutcome

    public init(id: String, title: String, shortcut: KeyStroke? = nil, perform: @escaping () async -> ActionOutcome) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.perform = perform
    }
}

@MainActor
public struct ResultItem: Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ResultIcon
    public var accessoryText: String?
    public var score: Double
    public var actions: [ResultAction]
    public var preview: (() -> AnyView)?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: ResultIcon,
        accessoryText: String? = nil,
        score: Double = 0.5,
        actions: [ResultAction],
        preview: (() -> AnyView)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessoryText = accessoryText
        self.score = score
        self.actions = actions
        self.preview = preview
    }
}
