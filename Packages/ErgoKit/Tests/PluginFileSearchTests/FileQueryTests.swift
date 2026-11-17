import Foundation
import Testing
@testable import PluginFileSearch

@Suite struct FileQueryTests {
    @Test func termsSplitOnWhitespace() {
        #expect(FileQuery.terms(from: "  报告  2024 ") == ["报告", "2024"])
        #expect(FileQuery.terms(from: "").isEmpty)
    }

    @Test func escapeSpecialCharacters() {
        #expect(FileQuery.escape(#"a"b*c\d"#) == #"a\"b\*c\\d"#)
    }

    @Test func predicateContainsAllTerms() {
        let s = FileQuery.predicateString(terms: ["foo", "bar"], searchContent: false)!
        #expect(s.contains("\"*foo*\"cd"))
        #expect(s.contains("\"*bar*\"cd"))
        #expect(s.contains(" && "))
        #expect(s.hasSuffix("kMDItemContentType != \"com.apple.application-bundle\""))
        #expect(!s.contains("kMDItemTextContent"))
        #expect(FileQuery.predicateString(terms: ["foo"], searchContent: true)!.contains("kMDItemTextContent"))
        #expect(FileQuery.predicateString(terms: [], searchContent: false) == nil)
    }

    @Test func predicateParsesAsNSPredicate() {
        let s = FileQuery.predicateString(terms: [#"we"ird*"#], searchContent: true)!
        #expect(NSPredicate(fromMetadataQueryString: s) != nil)
    }

    @Test func exclusions() {
        let home = "/Users/x"
        let pats = ["~/Library", "/System", "*/node_modules/*"]
        #expect(FileQuery.isExcluded("/Users/x/Library/Caches/a", patterns: pats, home: home))
        #expect(FileQuery.isExcluded("/System/Library", patterns: pats, home: home))
        #expect(FileQuery.isExcluded("/Users/x/p/node_modules/a/b.js", patterns: pats, home: home))
        #expect(!FileQuery.isExcluded("/Users/x/LibraryNotes/a", patterns: pats, home: home))
        #expect(!FileQuery.isExcluded("/Users/x/Documents/a.txt", patterns: pats, home: home))
    }

    @Test func scoringPrefersRecentAndNameMatch() {
        let now = Date()
        let home = "/Users/x"
        let recent = FileHit(path: "/Users/x/Documents/report.pdf", displayName: "report.pdf", isDirectory: false, lastUsed: now.addingTimeInterval(-60), modified: nil)
        let old = FileHit(path: "/Users/x/Documents/report.pdf", displayName: "report.pdf", isDirectory: false, lastUsed: now.addingTimeInterval(-90 * 86_400), modified: nil)
        let weak = FileHit(path: "/Users/x/Documents/annual-report-final.pdf", displayName: "annual-report-final.pdf", isDirectory: false, lastUsed: now.addingTimeInterval(-60), modified: nil)
        #expect(FileQuery.score(recent, query: "report", now: now, home: home) > FileQuery.score(old, query: "report", now: now, home: home))
        #expect(FileQuery.score(recent, query: "report", now: now, home: home) > FileQuery.score(weak, query: "report", now: now, home: home))
    }

    @Test func deepPathsPenalised() {
        let now = Date(), home = "/Users/x"
        let shallow = FileHit(path: "/Users/x/a/f.txt", displayName: "f.txt", isDirectory: false, lastUsed: now, modified: nil)
        let deep = FileHit(path: "/Users/x/a/b/c/d/e/f.txt", displayName: "f.txt", isDirectory: false, lastUsed: now, modified: nil)
        #expect(FileQuery.score(shallow, query: "f", now: now, home: home) > FileQuery.score(deep, query: "f", now: now, home: home))
    }
}
