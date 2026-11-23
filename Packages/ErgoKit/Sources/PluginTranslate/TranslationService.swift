import Foundation
import ErgoPluginKit

/// 一次翻译的结果：成功的译文，以及各引擎的失败原因（仅在没有任何结果时才展示给用户）。
struct TranslationOutcome {
    var results: [TranslationResult] = []
    var errors: [String] = []
    var detected: String?
}

@MainActor
final class TranslationService {
    enum Mode {
        /// 主搜索框：只取第一个目标语言；大模型是否参与由设置决定。
        case search
        /// `translate` 关键词：所有目标语言；大模型始终参与。
        case scope
    }

    private let context: any PluginContext
    private let settings: SettingsBox<TranslateSettings>
    private var cache: [String: TranslationResult] = [:]
    private var cacheOrder: [String] = []

    init(context: any PluginContext, settings: SettingsBox<TranslateSettings>) {
        self.context = context
        self.settings = settings
    }

    /// 当前启用的引擎，按优先级排序。
    func engines(for mode: Mode) -> [any TranslationEngine] {
        let s = settings.value
        var all: [String: any TranslationEngine] = [:]
        if s.useDictionary { all[EngineID.dictionary] = DictionaryEngine() }
        if s.useSystemTranslation { all[EngineID.system] = SystemTranslationEngine() }
        if mode == .scope || s.llmInSearch {
            for cfg in s.llmEngines where cfg.enabled {
                all[cfg.engineID] = LLMEngine(config: cfg, apiKey: context.secrets.secret(cfg.keyAccount))
            }
        }
        return s.orderedEngineIDs.compactMap { all[$0] }
    }

    func translate(_ text: String, mode: Mode) async -> TranslationOutcome {
        var outcome = TranslationOutcome()
        let s = settings.value
        guard let from = LanguageDetector.detect(text, among: LanguageDetector.languages(in: s.pairs)) else { return outcome }
        outcome.detected = from
        var targets = LanguageDetector.targets(for: from, pairs: s.pairs)
        if mode == .search { targets = Array(targets.prefix(1)) }
        let engines = engines(for: mode)
        for to in targets {
            for engine in engines {
                if Task.isCancelled { return outcome }
                let key = "\(engine.id)|\(from)>\(to)|\(text)"
                if let hit = cache[key] {
                    outcome.results.append(hit)
                    break
                }
                do {
                    guard let out = try await engine.translate(text, from: from, to: to) else { continue }
                    let translated = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 译文和原文一样（比如已经是目标语言），当作没有结果
                    guard !translated.isEmpty, translated.caseInsensitiveCompare(text) != .orderedSame else { continue }
                    let result = TranslationResult(text: translated, detail: out.detail, engineName: engine.name, from: from, to: to)
                    store(result, for: key)
                    outcome.results.append(result)
                    break
                } catch is CancellationError {
                    return outcome
                } catch {
                    if (error as? URLError)?.code == .cancelled { return outcome }
                    context.logger.info("translate \(engine.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    outcome.errors.append("\(engine.name)：\(error.localizedDescription)")
                }
            }
        }
        return outcome
    }

    private func store(_ result: TranslationResult, for key: String) {
        cache[key] = result
        cacheOrder.append(key)
        if cacheOrder.count > 100 {
            let drop = cacheOrder.removeFirst()
            cache[drop] = nil
        }
    }
}
