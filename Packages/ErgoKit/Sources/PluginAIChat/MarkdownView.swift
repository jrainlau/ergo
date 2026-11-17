import AppKit
import MarkdownUI
import SwiftUI

/// MarkdownUI 的内部包装：透明背景，代码块带复制按钮。
struct MarkdownView: View {
    let text: String

    var body: some View {
        // 越靠近内容的修饰符优先级越高，所以块样式要放在主题之前
        Markdown(text)
            .markdownBlockStyle(\.codeBlock) { configuration in
                CodeBlockView(configuration: configuration)
            }
            .markdownTheme(Self.theme)
            .textSelection(.enabled)
    }

    private static let theme = Theme.gitHub
        .text { BackgroundColor(.clear); FontSize(14) }
        .code { FontSize(.em(0.9)) }

}

private struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configuration.content, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.88)) }
                    .padding(10)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: 4, bottom: 8)
    }
}
