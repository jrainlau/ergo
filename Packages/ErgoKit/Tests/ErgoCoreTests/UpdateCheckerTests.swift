import Foundation
import Testing
@testable import ErgoCore

@Suite struct UpdateCheckerTests {
    private func release(_ tag: String, pre: Bool = false, draft: Bool = false, digest: String? = "sha256:ABCD", dmg: Bool = true) -> GitHubRelease {
        let base = URL(string: "https://github.com/jrainlau/ergo/releases/download/\(tag)/")!
        var assets: [GitHubRelease.Asset] = []
        if dmg {
            assets.append(.init(name: "Ergo-\(tag).dmg", size: 1, browserDownloadURL: base.appendingPathComponent("Ergo-\(tag).dmg"), digest: digest))
            assets.append(.init(name: "Ergo-\(tag).dmg.sha256", size: 1, browserDownloadURL: base.appendingPathComponent("Ergo-\(tag).dmg.sha256")))
        }
        return GitHubRelease(tagName: tag, draft: draft, prerelease: pre, htmlURL: URL(string: "https://github.com/jrainlau/ergo/releases/tag/\(tag)")!, assets: assets)
    }

    @Test func versionParsingAndOrdering() {
        #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
        #expect(AppVersion("v1.0.0") == AppVersion("1.0.0"))
        #expect(AppVersion("1.0") == nil)
        #expect(AppVersion("build-1") == nil)
        #expect(AppVersion("1.0.0-beta") == nil)
    }

    @Test func picksHighestVersionNotListOrder() {
        let rs = [release("0.1.8", pre: true), release("0.1.10", pre: true), release("0.1.3")]
        let info = UpdateChecker.pickUpdate(from: rs, current: AppVersion("0.1.5")!, includePrereleases: true)
        #expect(info?.version == AppVersion("0.1.10"))
        #expect(info?.sha256 == "abcd")
        #expect(info?.dmgName == "Ergo-0.1.10.dmg")
    }

    @Test func respectsPrereleaseDraftAndMissingDMG() {
        let rs = [release("0.2.0", pre: true), release("0.1.9", draft: true), release("0.1.8", dmg: false), release("0.1.6")]
        #expect(UpdateChecker.pickUpdate(from: rs, current: AppVersion("0.1.0")!, includePrereleases: false)?.version == AppVersion("0.1.6"))
        #expect(UpdateChecker.pickUpdate(from: rs, current: AppVersion("0.1.0")!, includePrereleases: true)?.version == AppVersion("0.2.0"))
    }

    @Test func noUpdateWhenCurrentIsNewest() {
        let rs = [release("0.1.8"), release("build-1")]
        #expect(UpdateChecker.pickUpdate(from: rs, current: AppVersion("0.1.8")!, includePrereleases: true) == nil)
    }

    @Test func fallsBackToChecksumFile() {
        let info = UpdateChecker.pickUpdate(from: [release("0.1.9", digest: nil)], current: AppVersion("0.1.0")!, includePrereleases: true)
        #expect(info?.sha256 == nil)
        #expect(info?.checksumFileURL?.lastPathComponent == "Ergo-0.1.9.dmg.sha256")
    }

    @Test func parsesChecksumFile() {
        let h = String(repeating: "a1", count: 32)
        #expect(UpdateChecker.parseChecksumFile("\(h.uppercased())  Ergo-0.1.9.dmg\n") == h)
        #expect(UpdateChecker.parseChecksumFile("nothex  file") == nil)
    }

    @Test func decodesGitHubPayload() throws {
        let json = """
        [{"tag_name":"0.1.8","draft":false,"prerelease":true,"body":null,"html_url":"https://github.com/jrainlau/ergo/releases/tag/0.1.8",
        "assets":[{"name":"Ergo-0.1.8.dmg","size":42,"browser_download_url":"https://github.com/x/Ergo-0.1.8.dmg","digest":"sha256:ff"}]}]
        """
        let rs = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        #expect(rs.first?.assets.first?.digest == "sha256:ff")
    }

    @Test func updateSettingsDecodeWithMissingKeys() throws {
        let s = try JSONDecoder().decode(UpdateSettingsData.self, from: Data("{}".utf8))
        #expect(s.autoCheck && s.includePrereleases && s.lastCheck == nil)
    }
}
