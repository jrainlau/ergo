import AppKit
import SwiftUI

struct LauncherTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var model: LauncherModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 24)
        f.usesSingleLineMode = true
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        f.lineBreakMode = .byTruncatingTail
        f.placeholderString = placeholder
        f.delegate = context.coordinator
        f.setAccessibilityLabel("搜索")
        model.textField = f
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.placeholderString != placeholder { f.placeholderString = placeholder }
        // 输入法组字期间不要覆盖文本
        if let editor = f.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        if f.stringValue != text { f.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherTextField
        init(_ p: LauncherTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            if parent.text != f.stringValue { parent.text = f.stringValue }
        }
    }
}
