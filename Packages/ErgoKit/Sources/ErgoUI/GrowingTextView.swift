import AppKit
import SwiftUI

/// 高度随内容在 minLines...maxLines 之间变化的多行输入框。
/// Return 提交；⇧Return / ⌥Return 换行；输入法组字期间 Return 不会提交。
public struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var font: NSFont
    var minLines: Int
    var maxLines: Int
    var focusToken: Int
    var onSubmit: () -> Void

    public init(
        text: Binding<String>, height: Binding<CGFloat>, placeholder: String = "",
        font: NSFont = .systemFont(ofSize: 15), minLines: Int = 1, maxLines: Int = 8,
        focusToken: Int = 0, onSubmit: @escaping () -> Void
    ) {
        _text = text
        _height = height
        self.placeholder = placeholder
        self.font = font
        self.minLines = minLines
        self.maxLines = maxLines
        self.focusToken = focusToken
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let tv = SubmitTextView(usingTextLayoutManager: false)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = font
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.placeholder = placeholder
        tv.delegate = context.coordinator
        tv.onSubmit = { [weak coordinator = context.coordinator] in coordinator?.parent.onSubmit() }
        tv.setAccessibilityLabel(placeholder.isEmpty ? "输入框" : placeholder)

        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.lastFocusToken = focusToken
        DispatchQueue.main.async { context.coordinator.recalcHeight() }
        return sv
    }

    public func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        tv.placeholder = placeholder
        if tv.font != font { tv.font = font }
        if !tv.hasMarkedText(), tv.string != text {
            tv.string = text
            tv.needsDisplay = true
            DispatchQueue.main.async { context.coordinator.recalcHeight() }
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: SubmitTextView?
        var lastFocusToken = 0
        init(_ p: GrowingTextView) { parent = p }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            recalcHeight()
        }

        func recalcHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let lineH = (tv.font ?? parent.font).boundingRectForFont.height
            let minH = lineH * CGFloat(parent.minLines) + tv.textContainerInset.height * 2
            let maxH = lineH * CGFloat(parent.maxLines) + tv.textContainerInset.height * 2
            let h = min(max(used, minH), maxH).rounded(.up)
            if abs(parent.height - h) > 0.5 { parent.height = h }
        }
    }
}

public final class SubmitTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var placeholder = ""

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeFirstResponder(self)
        }
    }

    public override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !hasMarkedText() {
            let mods = event.modifierFlags.intersection([.shift, .option, .command, .control])
            if mods.isEmpty { onSubmit(); return }
            if mods == .shift || mods == .option { insertNewlineIgnoringFieldEditor(nil); return }
        }
        super.keyDown(with: event)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 15), .foregroundColor: NSColor.placeholderTextColor]
        (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height), withAttributes: attrs)
    }

    public override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: lm.usedRect(for: tc).height + textContainerInset.height * 2)
    }
}
