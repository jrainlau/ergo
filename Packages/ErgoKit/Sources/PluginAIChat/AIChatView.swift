import AppKit
import SwiftUI
import ErgoPluginKit
import ErgoUI

struct AIChatView: View {
    let session: ChatSession
    let openSettings: () -> Void
    @State private var input = ""
    @State private var inputHeight: CGFloat = 24
    @State private var pinnedToBottom = true
    @State private var userScrolling = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                messageList
                if session.showHistory { historyOverlay }
            }
            Divider()
            inputBar
        }
    }

    // MARK: 顶栏
    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text(session.conversation?.title ?? "新对话").font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer()
            if !session.providers.isEmpty {
                Menu {
                    ForEach(session.providers) { p in
                        Section(p.name) {
                            let models = p.models.isEmpty ? [p.defaultModel].filter { !$0.isEmpty } : p.models
                            ForEach(models, id: \.self) { m in
                                Button(m) { session.select(provider: p, model: m) }
                            }
                        }
                    }
                } label: {
                    Text(session.model.isEmpty ? (session.currentProvider?.name ?? "选择模型") : session.model)
                        .font(.system(size: 12)).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("选择模型")
            }
            Button { session.newConversation() } label: { Label("新对话", systemImage: "square.and.pencil").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).help("新对话 ⌘N").accessibilityLabel("新对话")
            Button { session.toggleHistory() } label: { Label("历史", systemImage: "clock.arrow.circlepath").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).help("历史 ⌘Y").accessibilityLabel("历史会话")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(WindowDragHandle())
    }

    // MARK: 消息
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.messages.isEmpty { emptyState }
                    ForEach(session.messages) { m in
                        MessageRow(message: m, isLast: m.id == session.messages.last?.id, isStreaming: session.isStreaming, regenerate: { session.regenerate() })
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 48
            } action: { _, atBottom in
                if userScrolling { pinnedToBottom = atBottom }
            }
            .onChange(of: session.scrollTick) { _, _ in
                if pinnedToBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.conversation?.id) { _, _ in
                pinnedToBottom = true
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("向 AI 提问").font(.title3).foregroundStyle(.secondary)
            if session.providers.isEmpty {
                Text("还没有配置 AI 提供商").font(.caption).foregroundStyle(.orange)
                Button("打开设置", action: openSettings)
            } else {
                Text("↩ 发送  ⇧↩ 换行  Esc 停止生成").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    // MARK: 历史
    private var historyOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史会话").font(.headline)
                Spacer()
                Button("关闭") { session.showHistory = false }
            }
            .padding(12)
            Divider()
            if session.history.isEmpty {
                Text("暂无历史").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(session.history) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).lineLimit(1)
                                Text(Date(timeIntervalSince1970: c.updatedAt).formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.id == session.conversation?.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            Button(role: .destructive) { session.delete(c) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("删除会话")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { session.load(c) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: 输入
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let n = session.notice {
                HStack {
                    Text(n).font(.caption).foregroundStyle(.orange)
                    Button("打开设置", action: openSettings).buttonStyle(.link).font(.caption)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                GrowingTextView(text: $input, height: $inputHeight, placeholder: "向 AI 提问…", font: .systemFont(ofSize: 15), focusToken: session.focusToken) { submit() }
                    .frame(height: inputHeight)
                if session.isStreaming {
                    Button { session.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.borderless).help("停止生成 Esc").accessibilityLabel("停止生成")
                } else {
                    Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.borderless)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("发送")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func submit() {
        let t = input
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !session.isStreaming else { return }
        input = ""
        pinnedToBottom = true
        session.send(t)
    }
}

struct MessageRow: View {
    let message: ChatSession.UIMessage
    let isLast: Bool
    let isStreaming: Bool
    let regenerate: () -> Void
    @State private var hovering = false
    @State private var showReasoning = false

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.18)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("我：\(message.content)")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showReasoning) {
                        Text(message.reasoning).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label(message.status == .streaming && message.content.isEmpty ? "思考中…" : "思考过程", systemImage: "brain").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if message.content.isEmpty, message.status == .streaming, message.reasoning.isEmpty {
                    ProgressView().controlSize(.small)
                } else if !message.content.isEmpty {
                    MarkdownView(text: message.content)
                }
                if message.status == .error, let err = message.errorText {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(err).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("重试", action: regenerate).disabled(isStreaming)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
                }
                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: { Label("复制", systemImage: "doc.on.doc").font(.caption) }
                    if isLast && message.status != .streaming && message.status != .error {
                        Button(action: regenerate) { Label("重新生成", systemImage: "arrow.clockwise").font(.caption) }
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering && !message.content.isEmpty && message.status != .streaming ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
        }
    }
}
