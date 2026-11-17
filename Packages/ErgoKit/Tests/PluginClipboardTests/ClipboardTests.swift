import Foundation
import Testing
@testable import PluginClipboard

private func makeStore() throws -> (ClipboardStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-clip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (try ClipboardStore(directory: dir), dir)
}

private func item(_ title: String, text: String? = nil, hash: String? = nil, at time: Double, pinned: Bool = false) -> ClipItem {
    ClipItem(id: UUID().uuidString, kind: "text", title: title, textContent: text ?? title, blobPath: nil, thumbPath: nil, metaJSON: nil,
             contentHash: hash ?? UUID().uuidString, sourceBundleID: nil, sourceAppName: nil,
             createdAt: time, lastCopiedAt: time, copyCount: 1, isPinned: pinned)
}

@Suite struct ClipboardStoreTests {
    @Test func insertSearchOrder() throws {
        let (s, dir) = try makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        try s.insert(item("hello world", at: 100))
        try s.insert(item("foo bar", at: 200))
        try s.insert(item("hello pinned", at: 50, pinned: true))
        let all = try s.search("")
        #expect(all.map(\.title) == ["hello pinned", "foo bar", "hello world"])
        #expect(try s.search("hello").count == 2)
        #expect(try s.search("hello world").count == 1)
        #expect(try s.search("100%").isEmpty)
    }

    @Test func touchByHashBumpsCount() throws {
        let (s, dir) = try makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        try s.insert(item("a", hash: "H", at: 1))
        #expect(try s.touch(hash: "H", at: 500))
        #expect(!(try s.touch(hash: "missing")))
        let got = try s.search("a").first
        #expect(got?.copyCount == 2)
        #expect(got?.lastCopiedAt == 500)
    }

    @Test func cleanupByRetentionKeepsPinned() throws {
        let (s, dir) = try makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let t = now.timeIntervalSince1970
        try s.insert(item("old", at: t - 10_000))
        try s.insert(item("oldpinned", at: t - 10_000, pinned: true))
        try s.insert(item("new", at: t))
        let removed = try s.cleanup(retention: 1000, maxItems: 100, now: now)
        #expect(removed == 1)
        #expect(Set(try s.search("").map(\.title)) == ["oldpinned", "new"])
    }

    @Test func cleanupByMaxItems() throws {
        let (s, dir) = try makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<10 { try s.insert(item("n\(i)", at: Double(i))) }
        let removed = try s.cleanup(retention: nil, maxItems: 4)
        #expect(removed == 6)
        #expect(try s.count() == 4)
        #expect(try s.search("").first?.title == "n9")
    }

    @Test func deleteRemovesFiles() throws {
        let (s, dir) = try makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        var it = item("img", at: 1)
        it.blobPath = "x.png"
        try Data([1, 2]).write(to: s.blobsDir.appendingPathComponent("x.png"))
        try s.insert(it)
        try s.delete(id: it.id)
        #expect(!FileManager.default.fileExists(atPath: s.blobsDir.appendingPathComponent("x.png").path))
        #expect(try s.count() == 0)
    }
}

@Suite struct ClipboardProcessorTests {
    @Test func classifyText() {
        var raw = RawCapture(); raw.string = "  hello\nworld "
        let c = ClipboardProcessor.classify(raw, filter: ClipFilter())
        #expect(c?.kind == .text)
        #expect(c?.title == "hello")
    }

    @Test func classifyLink() {
        var raw = RawCapture(); raw.string = "https://example.com/a?b=1\n"
        #expect(ClipboardProcessor.classify(raw, filter: ClipFilter())?.kind == .link)
        raw.string = "see https://example.com"
        #expect(ClipboardProcessor.classify(raw, filter: ClipFilter())?.kind == .text)
    }

    @Test func classifyBlankIsNil() {
        var raw = RawCapture(); raw.string = " \n "
        #expect(ClipboardProcessor.classify(raw, filter: ClipFilter()) == nil)
    }

    @Test func classifyColor() {
        var raw = RawCapture(); raw.colorHex = "#FF0000"
        let c = ClipboardProcessor.classify(raw, filter: ClipFilter())
        #expect(c?.kind == .color)
        #expect(c?.meta.colorHex == "#FF0000")
    }

    @Test func filterDisablesKinds() {
        var raw = RawCapture(); raw.string = "hello"
        var f = ClipFilter(); f.text = false
        #expect(ClipboardProcessor.classify(raw, filter: f) == nil)
        var raw2 = RawCapture(); raw2.fileURLs = [URL(fileURLWithPath: "/tmp")]
        var f2 = ClipFilter(); f2.file = false
        #expect(ClipboardProcessor.classify(raw2, filter: f2) == nil)
    }

    @Test func classifyFolderAndMultiFile() {
        var raw = RawCapture(); raw.fileURLs = [URL(fileURLWithPath: "/tmp")]
        let c = ClipboardProcessor.classify(raw, filter: ClipFilter())
        #expect(c?.kind == .file)
        #expect(c?.meta.fileCategory == "folder")
        raw.fileURLs = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        #expect(ClipboardProcessor.classify(raw, filter: ClipFilter())?.title == "2 个文件")
    }

    @Test func hashStableAndDistinct() {
        var a = RawCapture(); a.string = "x"
        var b = RawCapture(); b.string = "x"
        var c = RawCapture(); c.string = "y"
        let f = ClipFilter()
        #expect(ClipboardProcessor.classify(a, filter: f)?.hash == ClipboardProcessor.classify(b, filter: f)?.hash)
        #expect(ClipboardProcessor.classify(a, filter: f)?.hash != ClipboardProcessor.classify(c, filter: f)?.hash)
    }
}
