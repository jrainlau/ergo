import Foundation
import Testing
@testable import PluginAppLauncher

@Suite struct AppIndexerTests {
    @Test func scansSystemApplications() {
        let entries = AppIndexer.scan(directories: ["/System/Applications"], depth: 1, excludedIDs: [])
        #expect(entries.contains { $0.path.hasSuffix("Calculator.app") })
        #expect(entries.allSatisfy { !$0.name.isEmpty })
    }

    @Test func finderAlwaysIncluded() {
        let entries = AppIndexer.scan(directories: [], depth: 1, excludedIDs: [])
        #expect(entries.contains { $0.path.hasSuffix("Finder.app") })
    }

    @Test func excludedBundleIDsRemoved() {
        let all = AppIndexer.scan(directories: ["/System/Applications"], depth: 1, excludedIDs: [])
        guard let calc = all.first(where: { $0.path.hasSuffix("Calculator.app") }), let id = calc.bundleID else { return }
        let filtered = AppIndexer.scan(directories: ["/System/Applications"], depth: 1, excludedIDs: [id])
        #expect(!filtered.contains { $0.bundleID == id })
    }

    @Test func scoringUsesAliasesAndPinyin() {
        let e = AppEntry(path: "/A/微信.app", bundleID: "x", name: "微信", aliases: ["WeChat"], pinyinFull: "weixin", pinyinInitials: "wx")
        #expect(AppIndexer.score(query: "wx", entry: e) != nil)
        #expect(AppIndexer.score(query: "wechat", entry: e)! > 0.8)
        #expect(AppIndexer.score(query: "微", entry: e)! > 0.8)
        #expect(AppIndexer.score(query: "zzz", entry: e) == nil)
    }

    @Test func cacheRoundTrip() throws {
        let e = [AppEntry(path: "/A.app", bundleID: nil, name: "A", aliases: [], pinyinFull: "", pinyinInitials: "")]
        let data = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode([AppEntry].self, from: data) == e)
    }
}
