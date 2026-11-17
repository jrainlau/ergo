import AppKit
import Observation
import ErgoPluginKit

@MainActor
@Observable
final class ChatSession {
    struct UIMessage: Identifiable, Equatable {
        var id: String
        var role: String
        var content: String
        var reasoning: String
        var status: MessageStatus
        var errorText: String?
    }

    private(set) var conversation: Conversation?
    private(set) var messages: [UIMessage] = []
    private(set) var isStreaming = false
    private(set) var history: [Conversation] = []
    var showHistory = false
    var scrollTick = 0
    var focusToken = 0
    var providerID: String?
    var model = ""
    var notice: String?

    @ObservationIgnored private let store: ChatStore
    @ObservationIgnored private let settings: SettingsBox<AIChatSettings>
    @ObservationIgnored private let secrets: any SecretStoring
    @ObservationIgnored private let client: any ChatClient
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(store: ChatStore, settings: SettingsBox<AIChatSettings>, secrets: any SecretStoring, client: any ChatClient = StreamingChatClient()) {
        self.store = store
        self.settings = settings
        self.secrets = secrets
        self.client = client
        applyDefaultProvider()
    }

    // MARK: 提供商

    var providers: [AIProviderConfig] { settings.value.providers }

    var currentProvider: AIProviderConfig? {
        let list = settings.value.providers
        return list.first { $0.id == providerID } ?? list.first { $0.id == settings.value.defaultProviderID } ?? list.first
    }

    func applyDefaultProvider() {
        let list = settings.value.providers
        let p = list.first { $0.id == settings.value.defaultProviderID } ?? list.first
        providerID = p?.id
        model = p?.defaultModel.isEmpty == false ? p!.defaultModel : (p?.models.first ?? "")
    }

    func select(provider: AIProviderConfig, model: String) {
        providerID = provider.id
        self.model = model
    }

    // MARK: 会话生命周期

    /// 进入作用域：最近的会话在时间窗口内就继续，否则等待新会话。
    func enter() {
        applyDefaultProvider()
        showHistory = false
        notice = nil
        if isStreaming { return }
        if let c = try? store.latestConversation(),
           Date().timeIntervalSince1970 - c.updatedAt < Double(settings.value.resumeMinutes * 60) {
            load(c)
        } else {
            newConversation()
        }
        focusToken += 1
    }

    func newConversation() {
        stop()
        conversation = nil
        messages = []
        showHistory = false
        notice = nil
        focusToken += 1
    }

    func load(_ c: Conversation) {
        stop()
        conversation = c
        messages = ((try? store.messages(in: c.id)) ?? []).map(Self.ui)
        if let pid = c.providerID, settings.value.providers.contains(where: { $0.id == pid }) {
            providerID = pid
            if let m = c.model, !m.isEmpty { model = m }
        }
        showHistory = false
        scrollTick += 1
        focusToken += 1
    }

    func toggleHistory() {
        if !showHistory { history = (try? store.conversations()) ?? [] }
        showHistory.toggle()
    }

    func delete(_ c: Conversation) {
        try? store.deleteConversation(id: c.id)
        history.removeAll { $0.id == c.id }
        if conversation?.id == c.id { newConversation(); showHistory = true }
    }

    private static func ui(_ m: StoredMessage) -> UIMessage {
        UIMessage(id: m.id, role: m.role, content: m.content, reasoning: m.reasoning, status: m.messageStatus, errorText: m.errorText)
    }

    // MARK: 发送

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !isStreaming else { return }
        guard currentProvider != nil else {
            notice = "还没有配置 AI 提供商，请先在设置中添加。"
            return
        }
        notice = nil
        let conv: Conversation
        if let c = conversation { conv = c } else {
            guard let c = try? store.createConversation(title: ChatStore.title(from: t), providerID: currentProvider?.id, model: model) else { return }
            conversation = c
            conv = c
        }
        guard let u = try? store.addMessage(conversationID: conv.id, role: "user", content: t) else { return }
        messages.append(Self.ui(u))
        generate()
    }

    func regenerate() {
        guard !isStreaming else { return }
        if let last = messages.last, last.role == "assistant" {
            try? store.deleteMessage(id: last.id)
            messages.removeLast()
        }
        guard messages.last?.role == "user" else { return }
        generate()
    }

    private func generate() {
        guard let conv = conversation, let provider = currentProvider else { return }
        let modelName = model.isEmpty ? provider.defaultModel : model
        guard let a = try? store.addMessage(conversationID: conv.id, role: "assistant", content: "", status: .streaming) else { return }
        messages.append(Self.ui(a))
        scrollTick += 1
        isStreaming = true
        try? store.touch(conv.id, model: modelName, providerID: provider.id)

        let s = settings.value
        let turns = messages.dropLast().filter { $0.status != .error || !$0.content.isEmpty }.map { ChatTurn(role: $0.role, content: $0.content) }
        let context = ContextBuilder.build(turns, maxMessages: s.contextMessages, maxChars: s.contextMaxChars)
        let key = secrets.secret(provider.keyAccount)
        let req = ChatRequest(kind: provider.kind, baseURL: provider.baseURL, apiKey: key, extraHeaders: provider.extraHeaders,
                              model: modelName, system: s.systemPrompt, messages: context, temperature: s.temperature)
        let msgID = a.id
        let client = self.client
        let store = self.store

        streamTask = Task { [weak self] in
            var content = ""
            var reasoning = ""
            var lastFlush = Date.distantPast
            var failure: String?
            do {
                for try await d in client.stream(req) {
                    switch d {
                    case .text(let t): content += t
                    case .reasoning(let r): reasoning += r
                    }
                    // 节流到约 10Hz，避免 Markdown 反复重解析
                    if Date().timeIntervalSince(lastFlush) >= 0.1 {
                        lastFlush = Date()
                        self?.publish(msgID, content, reasoning, .streaming, nil)
                    }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            let status: MessageStatus = failure != nil ? .error : .done
            try? store.update(messageID: msgID, content: content, reasoning: reasoning, status: status, errorText: failure)
            try? store.touch(conv.id, model: nil, providerID: nil)
            self?.publish(msgID, content, reasoning, status, failure)
            self?.isStreaming = false
            self?.streamTask = nil
        }
    }

    private func publish(_ id: String, _ content: String, _ reasoning: String, _ status: MessageStatus, _ err: String?) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].content = content
        messages[i].reasoning = reasoning
        messages[i].status = status
        messages[i].errorText = err
        scrollTick += 1
    }

    func stop() {
        streamTask?.cancel()
    }

    var lastAssistantText: String? {
        messages.last(where: { $0.role == "assistant" && !$0.content.isEmpty })?.content
    }
}
