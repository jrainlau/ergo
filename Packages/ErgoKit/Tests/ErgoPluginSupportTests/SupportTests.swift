import Foundation
import Testing
@testable import ErgoPluginSupport

@Suite struct FuzzyMatcherTests {
    @Test func exactAndPrefix() {
        #expect(FuzzyMatcher.score(query: "safari", candidate: "Safari") == 1.0)
        let p = FuzzyMatcher.score(query: "saf", candidate: "Safari")!
        #expect(p > 0.9)
    }

    @Test func wordInitials() {
        let s = FuzzyMatcher.score(query: "vsc", candidate: "Visual Studio Code")
        #expect(s == 0.8)
        #expect(FuzzyMatcher.score(query: "ps", candidate: "PhotoShop") == 0.8)
    }

    @Test func pinyin() {
        let p = Pinyin.convert("微信")
        #expect(p.full == "weixin")
        #expect(p.initials == "wx")
        #expect(FuzzyMatcher.score(query: "wx", candidate: "微信", pinyinFull: p.full, pinyinInitials: p.initials) != nil)
        let s = Pinyin.convert("系统设置")
        #expect(s.initials == "xtsz")
        #expect(FuzzyMatcher.score(query: "xtsz", candidate: "系统设置", pinyinFull: s.full, pinyinInitials: s.initials)! >= 0.8)
        #expect(FuzzyMatcher.score(query: "weix", candidate: "微信", pinyinFull: p.full, pinyinInitials: p.initials)! >= 0.85)
    }

    @Test func mixedPinyin() {
        let p = Pinyin.convert("QQ音乐")
        #expect(p.initials == "qqyl")
    }

    @Test func substringAndSubsequence() {
        let sub = FuzzyMatcher.score(query: "tud", candidate: "Visual Studio")!
        #expect(sub == 0.6)
        let word = FuzzyMatcher.score(query: "stu", candidate: "Visual Studio")!
        #expect(word == 0.7)
        let seq = FuzzyMatcher.score(query: "vsl", candidate: "Visual")!
        #expect(seq > 0.3 && seq < 0.6)
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "Safari") == nil)
        #expect(FuzzyMatcher.score(query: "", candidate: "Safari") == nil)
    }

    @Test func caseAndWidthInsensitive() {
        #expect(FuzzyMatcher.score(query: "ＳＡＦ", candidate: "safari")! > 0.9)
    }
}

@Suite struct SSEParserTests {
    @Test func openAIStyle() {
        var p = SSEParser()
        let e = p.feed(line: "data: {\"a\":1}")
        #expect(e == SSEEvent(event: nil, data: "{\"a\":1}"))
        #expect(p.feed(line: "data: [DONE]")?.data == "[DONE]")
    }

    @Test func anthropicStyle() {
        var p = SSEParser()
        #expect(p.feed(line: "event: content_block_delta") == nil)
        let e = p.feed(line: "data: {\"x\":2}")
        #expect(e == SSEEvent(event: "content_block_delta", data: "{\"x\":2}"))
        #expect(p.feed(line: "data: {}")?.event == nil)
    }

    @Test func commentsAndBlank() {
        var p = SSEParser()
        #expect(p.feed(line: ": ping") == nil)
        #expect(p.feed(line: "") == nil)
    }
}

@Suite struct FormatHelperTests {
    @Test func relativeDate() {
        let now = Date()
        #expect(FormatHelpers.relativeDateTime(now, now: now).hasPrefix("今天"))
        let y = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(FormatHelpers.relativeDateTime(y, now: now).hasPrefix("昨天"))
    }
}
