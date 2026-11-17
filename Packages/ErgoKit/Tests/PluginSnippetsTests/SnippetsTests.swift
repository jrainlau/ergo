import Foundation
import Testing
@testable import PluginSnippets

private func ctx() -> ExpansionContext {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    // 2026-03-05 14:07:00 UTC
    let d = Date(timeIntervalSince1970: 1_772_719_620)
    return ExpansionContext(now: d, clipboard: "CLIP", uuid: { "UUID-1" }, calendar: cal)
}

@Suite struct ExpanderTests {
    @Test func plainText() {
        #expect(SnippetExpander.expand("hello", context: ctx()) == ExpandedSnippet(text: "hello", cursorBack: nil))
    }

    @Test func datePlaceholders() {
        let c = ctx()
        let date = SnippetExpander.expand("{date}", context: c).text
        #expect(date.count == 10 && date.hasPrefix("2026-"))
        #expect(SnippetExpander.expand("{time}", context: c).text.count == 5)
        #expect(SnippetExpander.expand("{datetime}", context: c).text == "\(date) \(SnippetExpander.expand("{time}", context: c).text)")
        #expect(SnippetExpander.expand("{date:yyyy/MM}", context: c).text == String(date.prefix(7)).replacingOccurrences(of: "-", with: "/"))
    }

    @Test func clipboardAndUUID() {
        #expect(SnippetExpander.expand("a{clipboard}b{uuid}", context: ctx()).text == "aCLIPbUUID-1")
    }

    @Test func cursorOffset() {
        let r = SnippetExpander.expand("Hi {cursor}, bye", context: ctx())
        #expect(r.text == "Hi , bye")
        #expect(r.cursorBack == 5)
        #expect(SnippetExpander.expand("x{cursor}", context: ctx()).cursorBack == nil)
        #expect(SnippetExpander.expand("{cursor}ab", context: ctx()).cursorBack == 2)
        // 多个 cursor 只取第一个
        #expect(SnippetExpander.expand("a{cursor}b{cursor}c", context: ctx()).cursorBack == 2)
    }

    @Test func cursorCountsAfterExpansion() {
        let r = SnippetExpander.expand("{cursor}{clipboard}", context: ctx())
        #expect(r.text == "CLIP")
        #expect(r.cursorBack == 4)
    }

    @Test func escapedBraces() {
        #expect(SnippetExpander.expand("{{date}}", context: ctx()).text == "{date}")
        #expect(SnippetExpander.expand("a {{ b }} c", context: ctx()).text == "a { b } c")
    }

    @Test func unknownTokensStayLiteral() {
        #expect(SnippetExpander.expand("{foo} {", context: ctx()).text == "{foo} {")
        #expect(SnippetExpander.expand("}", context: ctx()).text == "}")
        #expect(SnippetExpander.expand("{date:}", context: ctx()).text == "{date:}")
    }

    @Test func chineseAndEmoji() {
        let r = SnippetExpander.expand("你好👨‍👩‍👧{cursor}世界", context: ctx())
        #expect(r.cursorBack == 2)
    }
}

@Suite struct StoreTests {
    @Test func seedsDefaults() throws {
        let s = try SnippetStore()
        #expect(try s.collections().map(\.name) == ["默认"])
        #expect(try s.snippets().count == 2)
    }

    @Test func crud() throws {
        let s = try SnippetStore()
        let c = try s.addCollection(name: "工作")
        var sn = try s.addSnippet(collectionID: c.id, title: "地址", keyword: "dz", content: "北京")
        sn.content = "上海"
        try s.update(sn)
        #expect(try s.snippet(id: sn.id)?.content == "上海")
        try s.recordUse(id: sn.id)
        #expect(try s.snippet(id: sn.id)?.useCount == 1)
        try s.deleteSnippet(id: sn.id)
        #expect(try s.snippet(id: sn.id) == nil)
    }

    @Test func deleteCollectionCascades() throws {
        let s = try SnippetStore()
        let c = try s.addCollection(name: "x")
        _ = try s.addSnippet(collectionID: c.id, title: "a")
        try s.deleteCollection(id: c.id)
        #expect(try s.snippets(in: c.id).isEmpty)
    }

    @Test func reorder() throws {
        let s = try SnippetStore()
        let c = try s.addCollection(name: "r")
        let a = try s.addSnippet(collectionID: c.id, title: "a")
        let b = try s.addSnippet(collectionID: c.id, title: "b")
        try s.reorder(ids: [b.id, a.id])
        #expect(try s.snippets(in: c.id).map(\.title) == ["b", "a"])
    }

    @Test func exportImportRoundTrip() throws {
        let a = try SnippetStore()
        let c = try a.addCollection(name: "工作")
        _ = try a.addSnippet(collectionID: c.id, title: "地址", keyword: "dz", content: "北京\n朝阳", useCount: 3)
        let data = try a.exportLibrary()

        let b = try SnippetStore()
        // 默认分组的两条示例相同会被跳过，只新增“工作”里的 1 条
        #expect(try b.importLibrary(data) == 1)
        let file = try JSONDecoder().decode(SnippetLibraryFile.self, from: data)
        let again = try JSONDecoder().decode(SnippetLibraryFile.self, from: b.exportLibrary())
        #expect(again == file)
        // 重复导入不产生重复项
        #expect(try b.importLibrary(data) == 0)
    }

    @Test func importRejectsGarbage() throws {
        let s = try SnippetStore()
        #expect(throws: (any Error).self) { try s.importLibrary(Data("nope".utf8)) }
    }
}

@Suite struct MatcherTests {
    private func snip(_ title: String, _ kw: String = "", _ content: String = "") -> Snippet {
        Snippet(id: UUID().uuidString, collectionID: "c", title: title, keyword: kw, content: content, useCount: 0, lastUsedAt: nil, sortOrder: 0, createdAt: 0, updatedAt: 0)
    }

    @Test func exactKeywordWins() {
        #expect(SnippetMatcher.score(query: "dz", snippet: snip("家庭地址", "dz")) == 1.0)
        #expect(SnippetMatcher.score(query: "DZ", snippet: snip("x", "dz")) == 1.0)
    }

    @Test func titleAndContent() {
        let t = SnippetMatcher.score(query: "地址", snippet: snip("家庭地址"))
        #expect(t != nil && t! > 0.5)
        #expect(SnippetMatcher.score(query: "北京", snippet: snip("a", "", "我住在北京")) == 0.5)
        #expect(SnippetMatcher.score(query: "zzz", snippet: snip("a", "b", "c")) == nil)
        #expect(SnippetMatcher.score(query: "", snippet: snip("a")) == nil)
    }

    @Test func pinyinInitials() {
        #expect(SnippetMatcher.score(query: "jtdz", snippet: snip("家庭地址")) != nil)
    }

    @Test func boostBounded() {
        #expect(SnippetMatcher.useBoost(0) == 0)
        #expect(SnippetMatcher.useBoost(100000) <= 0.05)
    }
}
