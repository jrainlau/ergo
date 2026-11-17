import AppKit
import SwiftUI
import ErgoCore
import ErgoPluginKit
import ErgoUI

public struct LauncherRootView: View {
    @Bindable var model: LauncherModel

    public init(model: LauncherModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            if model.showsHostInput {
                InputRow(model: model)
            }
            content
        }
        .frame(width: model.panelWidth, height: model.panelHeight, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.scope, case .custom = s.scope.style {
            s.customView
        } else if let s = model.scope, case .listWithPreview(let ratio) = s.scope.style {
            Divider()
            PreviewSplitView(model: model, ratio: ratio)
        } else {
            if let p = model.inlinePanel {
                Divider()
                p.panel.view.frame(height: p.panel.height)
            }
            if !model.results.isEmpty, !(model.inlinePanel?.panel.exclusive ?? false) {
                Divider()
                ResultListView(model: model)
            }
        }
    }
}

struct InputRow: View {
    @Bindable var model: LauncherModel

    var body: some View {
        HStack(spacing: 10) {
            if let s = model.scope {
                ScopeChip(name: s.name)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            LauncherTextField(
                text: $model.query,
                placeholder: model.scope?.scope.placeholder ?? "搜索应用、文件、计算…",
                model: model
            )
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.inputHeight)
        .background(WindowDragHandle())
    }
}

struct ScopeChip: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            .foregroundStyle(Color.accentColor)
    }
}

struct ResultListView: View {
    @Bindable var model: LauncherModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, d in
                        ResultRowView(
                            item: d.item,
                            hint: index == model.selectedIndex ? "↩" : (index < 9 ? "⌘\(index + 1)" : nil),
                            isSelected: index == model.selectedIndex
                        )
                        .id(d.id)
                        .onHover { inside in if inside { model.hover(index) } }
                        .onTapGesture { model.activate(index: index) }
                    }
                }
                .padding(Theme.listPadding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedIndex) { _, new in
                guard model.results.indices.contains(new) else { return }
                proxy.scrollTo(model.results[new].id)
            }
            .overlay(alignment: .bottomTrailing) {
                if model.showActionPanel { ActionPanelView(model: model) }
            }
        }
    }
}

struct PreviewSplitView: View {
    @Bindable var model: LauncherModel
    let ratio: CGFloat

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ResultListView(model: model)
                    .frame(width: geo.size.width * (1 - ratio) + 40)
                Divider()
                Group {
                    if let preview = model.selectedItem?.item.preview {
                        preview().id(model.selectedItem?.id)
                    } else {
                        Color.clear
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct ActionPanelView: View {
    @Bindable var model: LauncherModel

    var body: some View {
        if let item = model.selectedItem {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(item.item.actions.enumerated()), id: \.element.id) { i, a in
                    HStack {
                        Text(a.title).font(.system(size: 13))
                        Spacer(minLength: 16)
                        if let sc = a.shortcut {
                            Text(KeyHint.string(sc)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(i == model.actionSelection ? Theme.selectionFill : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.perform(a, on: item); model.showActionPanel = false }
                }
            }
            .padding(6)
            .frame(width: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
            .shadow(radius: 8, y: 2)
            .padding(12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("动作列表")
        }
    }
}

public enum KeyHint {
    public static func string(_ k: KeyStroke) -> String {
        var s = ""
        if k.modifiers.contains(.control) { s += "⌃" }
        if k.modifiers.contains(.option) { s += "⌥" }
        if k.modifiers.contains(.shift) { s += "⇧" }
        if k.modifiers.contains(.command) { s += "⌘" }
        switch k.key {
        case .enter: s += "↩"
        case .escape: s += "⎋"
        case .deleteBackward: s += "⌫"
        case .tab: s += "⇥"
        case .up: s += "↑"
        case .down: s += "↓"
        case .left: s += "←"
        case .right: s += "→"
        case .pageUp: s += "⇞"
        case .pageDown: s += "⇟"
        case .character(let c): s += String(c).uppercased()
        }
        return s
    }
}
