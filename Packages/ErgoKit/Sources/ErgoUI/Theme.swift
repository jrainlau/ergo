import SwiftUI

public enum Theme {
    public static let panelCornerRadius: CGFloat = 22
    public static let rowCornerRadius: CGFloat = 10
    public static let rowHeight: CGFloat = 48
    public static let inputHeight: CGFloat = 60
    public static let listPadding: CGFloat = 8
    public static let inputFontSize: CGFloat = 24
    public static let selectionFill = Color.accentColor.opacity(0.22)
}

public extension View {
    func ergoReduceMotion(_ animation: Animation?) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }
}
