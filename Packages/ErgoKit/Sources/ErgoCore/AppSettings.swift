import Foundation
import ErgoPluginKit

public nonisolated enum ScreenChoice: String, Codable, CaseIterable, Sendable {
    case mouse, main, last
    public var title: String {
        switch self {
        case .mouse: "鼠标所在屏幕"
        case .main: "主屏幕"
        case .last: "上次所在屏幕"
        }
    }
}

public nonisolated enum PanelMaterial: String, Codable, CaseIterable, Sendable {
    case regular, clear, opaque
    public var title: String {
        switch self {
        case .regular: "常规玻璃"
        case .clear: "透明玻璃"
        case .opaque: "不透明"
        }
    }
}

public nonisolated enum AppearanceChoice: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

public nonisolated struct LauncherPlacement: Codable, Equatable, Sendable {
    public var screenUUID: String
    public var centerXRatio: Double
    public var topOffset: Double
    public init(screenUUID: String, centerXRatio: Double, topOffset: Double) {
        self.screenUUID = screenUUID
        self.centerXRatio = centerXRatio
        self.topOffset = topOffset
    }
}

public nonisolated struct AppSettingsData: Codable, Equatable, Sendable {
    public var showOnScreen: ScreenChoice = .mouse
    public var hideOnResignKey: Bool = true
    public var keepLastQuery: Bool = false
    public var maxVisibleRows: Int = 8
    public var panelWidth: Double = 720
    public var showMenuBarIcon: Bool = true
    public var material: PanelMaterial = .regular
    public var appearance: AppearanceChoice = .system
    public var hasCompletedOnboarding: Bool = false
    public var doubleTapInterval: Double = 0.3
    public var placement: LauncherPlacement? = nil

    public init() {}
}

public typealias AppSettings = SettingsBox<AppSettingsData>
