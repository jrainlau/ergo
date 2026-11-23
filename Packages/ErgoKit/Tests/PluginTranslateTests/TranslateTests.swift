import Foundation
import Testing
@testable import PluginTranslate

// MARK: - 语言识别

@Suite struct LanguageDetectorTests {
    let zhEn = ["zh-Hans", "en"]

    @Test func chineseAndEnglish() {
        #expect(LanguageDetector.detect("你好，世界", among: zhEn) == "zh-Hans")
        #expect(LanguageDetector.detect("hello world", among: zhEn) == "en")
        #expect(LanguageDetector.detect("hello", among: zhEn) == "en")
        #expect(LanguageDetector.detect("苹果", among: zhEn) == "zh-Hans")
    }

    @Test func mixedTextFollowsDominantScript() {
        #expect(LanguageDetector.detect("我喜欢 iPhone", among: zhEn) == "zh-Hans")
        #expect(LanguageDetector.detect("I really like this app 很好", among: zhEn) == "en")
    }

    @Test func japaneseNeedsKana() {
        let langs = ["zh-Hans", "en", "ja"]
        #expect(LanguageDetector.detect("ありがとう", among: langs) == "ja")
        #expect(LanguageDetector.detect("谢谢", among: langs) == "zh-Hans")
    }

    @Test func koreanByHangul() {
        #expect(LanguageDetector.detect("감사합니다", among: ["ko", "en"]) == "ko")
    }

    @Test func emptyCandidates() {
        #expect(LanguageDetector.detect("hello", among: []) == nil)
    }

    @Test func targetsFollowPairOrder() {
        let pairs = [LanguagePair(a: "zh-Hans", b: "en"), LanguagePair(a: "zh-Hans", b: "ja"), LanguagePair(a: "en", b: "fr")]
        #expect(LanguageDetector.targets(for: "zh-Hans", pairs: pairs) == ["en", "ja"])
        #expect(LanguageDetector.targets(for: "en", pairs: pairs) == ["zh-Hans", "fr"])
        #expect(LanguageDetector.targets(for: "ja", pairs: pairs) == ["zh-Hans"])
        #expect(LanguageDetector.targets(for: "de", pairs: pairs).isEmpty)
    }

    @Test func traditionalChineseSharesPair() {
        #expect(LanguageDetector.targets(for: "zh-Hant", pairs: [.chineseEnglish]) == ["en"])
    }

    @Test func languagesDeduped() {
        let pairs = [LanguagePair(a: "zh-Hans", b: "en"), LanguagePair(a: "en", b: "ja")]
        #expect(LanguageDetector.languages(in: pairs) == ["zh-Hans", "en", "ja"])
    }
}

// MARK: - 启发式过滤

@Suite struct HeuristicsTests {
    @Test(arguments: ["hello", "你好", "good morning", "How are you today?", "苹果手机"])
    func translatable(_ s: String) {
        #expect(TranslateHeuristics.isTranslatable(s, maxChars: 200))
    }

    @Test(arguments: ["1+1", "12345", "2*3=6", "https://example.com", "/usr/bin", "~/Desktop", "a@b.com", "x", "=1+2", "   "])
    func notTranslatable(_ s: String) {
        #expect(!TranslateHeuristics.isTranslatable(s, maxChars: 200))
    }

    @Test func tooLong() {
        #expect(!TranslateHeuristics.isTranslatable(String(repeating: "a", count: 201), maxChars: 200))
        #expect(TranslateHeuristics.isTranslatable(String(repeating: "a", count: 201), maxChars: 300))
    }
}

// MARK: - 词典词条解析（样本来自 macOS 自带的牛津英汉汉英词典）

@Suite struct DictionaryParserTests {
    @Test func helloToChinese() {
        let raw = "hello | BrE həˈləʊ, hɛˈləʊ, AmE həˈloʊ, hɛˈloʊ | A. noun 问候 wènhòu B. exclamation ① (greeting) 你好 nǐ hǎo; (on phone) 喂 wèi ② British (in surprise) 嘿 hēi "
        let out = DictionaryParser.parse(raw, term: "hello", sourceIsChinese: false)
        #expect(out?.text == "问候；你好；喂；嘿")
        #expect(out?.detail == raw.trimmingCharacters(in: .whitespaces))
    }

    @Test func appleToChineseDropsExamples() {
        let raw = "apple | BrE ˈapl, AmE ˈæp(ə)l | noun (fruit) 苹果 píngguǒ; (tree) 苹果树 píngguǒ shù▸ the apple of sb's eye figurative 掌上明珠▸ an apple a day keeps the doctor away proverb 天天吃苹果，医生远离我 "
        #expect(DictionaryParser.parse(raw, term: "apple", sourceIsChinese: false)?.text == "苹果；苹果树")
    }

    @Test func exampleBeforeSecondPartOfSpeechIsKept() {
        let raw = "thank you | BrE ˈθaŋk juː, AmE ˌθæŋk ˌju | A. noun plural thank yous 谢意 xièyì▸ to say one's thank yous to sb 向某人表示感谢 B. exclamation 谢谢你 xièxie nǐ▸ thank you very much 非常感谢 "
        #expect(DictionaryParser.parse(raw, term: "thank you", sourceIsChinese: false)?.text == "谢意；谢谢你")
    }

    @Test func pinyinMatchIsRejected() {
        #expect(DictionaryParser.parse("闰 （閏） rùn noun ［Astronomy］ intercalation", term: "run", sourceIsChinese: false) == nil)
    }

    @Test func appleToEnglish() {
        #expect(DictionaryParser.parse("苹果 pínɡɡuǒ noun apple ", term: "苹果", sourceIsChinese: true)?.text == "apple")
    }

    @Test func worldToEnglishMultipleSenses() {
        let raw = "世界 shìjiè noun ① （一切事物） world▸ 创造新世界 create a new world ▸ 世界闻名 be world-famous ② ［Buddhism］ universe→ 大千世界 ③ （全球） all parts of the world▸ 他们的产品经销世界各地。 Their products are sold worldwide. ④ （风气） mores of the world ⑤ （领域） realm▸ 儿童世界 world of children "
        #expect(DictionaryParser.parse(raw, term: "世界", sourceIsChinese: true)?.text == "world; universe; all parts of the world; mores of the world")
    }

    @Test func verbEntryStripsPartOfSpeech() {
        let raw = "学习 xuéxí verb ① （获取知识技能） study▸ 学习文化 learn to read and write ② （吸取他人优点） follow the example of▸ 学习别人的长处 emulate others’ strong points "
        #expect(DictionaryParser.parse(raw, term: "学习", sourceIsChinese: true)?.text == "study; follow the example of")
    }

    @Test func chineseEntryMustStartWithTerm() {
        #expect(DictionaryParser.parse("蚺 rán → 蚺蛇", term: "ran", sourceIsChinese: true) == nil)
    }

    @Test func emptyIsNil() {
        #expect(DictionaryParser.parse("   ", term: "x", sourceIsChinese: false) == nil)
    }
}

// MARK: - 大模型请求与响应

@Suite struct LLMTranslatorTests {
    let openAI = LLMEngineConfig(name: "t", kind: .openAICompatible, baseURL: "https://api.example.com/v1/", model: "m")
    let anthropic = LLMEngineConfig(name: "a", kind: .anthropic, baseURL: "https://api.anthropic.com/v1", model: "claude")

    @Test func openAIRequest() throws {
        let req = try LLMTranslator.buildRequest(openAI, apiKey: "sk-1", text: "hello", from: "en", to: "zh-Hans")
        #expect(req.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let data = try #require(req.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "m")
        #expect(body["stream"] as? Bool == false)
        let msgs = try #require(body["messages"] as? [[String: String]])
        #expect(msgs.last == ["role": "user", "content": "hello"])
        #expect(msgs.first?["role"] == "system")
        #expect(msgs.first?["content"]?.contains("简体中文") == true)
    }

    @Test func anthropicRequest() throws {
        let req = try LLMTranslator.buildRequest(anthropic, apiKey: "k", text: "你好", from: "zh-Hans", to: "en")
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") != nil)
        let data = try #require(req.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["system"] is String)
    }

    @Test func keyRules() {
        #expect(throws: TranslateError.missingKey) { try LLMTranslator.buildRequest(openAI, apiKey: " ", text: "a", from: "en", to: "zh-Hans") }
        var local = openAI
        local.requiresKey = false
        #expect(throws: Never.self) { try LLMTranslator.buildRequest(local, apiKey: nil, text: "a", from: "en", to: "zh-Hans") }
        var noModel = openAI
        noModel.model = " "
        #expect(throws: TranslateError.noModel) { try LLMTranslator.buildRequest(noModel, apiKey: "k", text: "a", from: "en", to: "zh-Hans") }
        var badURL = openAI
        badURL.baseURL = "not a url"
        #expect(throws: TranslateError.invalidURL) { try LLMTranslator.buildRequest(badURL, apiKey: "k", text: "a", from: "en", to: "zh-Hans") }
    }

    @Test func extraPromptAppended() {
        let p = LLMTranslator.systemPrompt(from: "en", to: "zh-Hans", extra: "  口语化  ")
        #expect(p.hasSuffix("口语化"))
        #expect(!LLMTranslator.systemPrompt(from: "en", to: "zh-Hans", extra: "").hasSuffix("\n"))
    }

    @Test func parseResponses() throws {
        let o = Data(#"{"choices":[{"message":{"role":"assistant","content":" 你好 "}}]}"#.utf8)
        #expect(try LLMTranslator.parseResponse(o, kind: .openAICompatible) == "你好")
        let a = Data(#"{"content":[{"type":"text","text":"你"},{"type":"text","text":"好"}]}"#.utf8)
        #expect(try LLMTranslator.parseResponse(a, kind: .anthropic) == "你好")
        let think = Data(#"{"choices":[{"message":{"content":"<think>hmm</think>\n你好"}}]}"#.utf8)
        #expect(try LLMTranslator.parseResponse(think, kind: .openAICompatible) == "你好")
        #expect(throws: TranslateError.badResponse) { try LLMTranslator.parseResponse(Data("nope".utf8), kind: .openAICompatible) }
        #expect(throws: TranslateError.badResponse) { try LLMTranslator.parseResponse(Data(#"{"choices":[]}"#.utf8), kind: .openAICompatible) }
    }

    @Test func translateUsesTransportAndReportsHTTPErrors() async throws {
        let ok = try await LLMTranslator.translate(openAI, apiKey: "k", text: "hi", from: "en", to: "zh-Hans") { _ in
            (Data(#"{"choices":[{"message":{"content":"嗨"}}]}"#.utf8), 200)
        }
        #expect(ok == "嗨")
        await #expect(throws: TranslateError.http(401, "bad key")) {
            _ = try await LLMTranslator.translate(openAI, apiKey: "k", text: "hi", from: "en", to: "zh-Hans") { _ in
                (Data(#"{"error":{"message":"bad key"}}"#.utf8), 401)
            }
        }
    }
}

// MARK: - 设置

@Suite struct TranslateSettingsTests {
    @Test func defaultsAreChineseEnglishOnly() {
        let s = TranslateSettings()
        #expect(s.pairs == [.chineseEnglish])
        #expect(s.llmEngines.isEmpty)
        #expect(!s.llmInSearch)
    }

    @Test func decodingOldOrPartialJSONKeepsDefaults() throws {
        let s = try JSONDecoder().decode(TranslateSettings.self, from: Data(#"{"autoInSearch":false}"#.utf8))
        #expect(!s.autoInSearch)
        #expect(s.pairs == [.chineseEnglish])
        #expect(s.useDictionary)
    }

    @Test func roundTrip() throws {
        var s = TranslateSettings()
        s.llmEngines = [LLMEngineConfig(id: "x", name: "DS", baseURL: "https://a", model: "m")]
        s.pairs.append(LanguagePair(a: "en", b: "ja"))
        let back = try JSONDecoder().decode(TranslateSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func engineOrderMergesNewAndDropsRemoved() {
        var s = TranslateSettings()
        s.llmEngines = [LLMEngineConfig(id: "a", name: "A", baseURL: "u"), LLMEngineConfig(id: "b", name: "B", baseURL: "u")]
        #expect(s.orderedEngineIDs == ["dictionary", "system", "llm.a", "llm.b"])
        s.engineOrder = ["llm.b", "gone", "dictionary"]
        #expect(s.orderedEngineIDs == ["llm.b", "dictionary", "system", "llm.a"])
    }
}
