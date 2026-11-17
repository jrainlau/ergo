import Foundation
import Testing
import ErgoPluginKit
@testable import ErgoCore

private struct Sample: Codable, Equatable { var a: Int; var b: String }

@Suite struct SettingsStoreTests {
    @Test func roundTripAndScope() {
        let d = UserDefaults(suiteName: "ergo.test.\(UUID().uuidString)")!
        let s = SettingsStore(defaults: d)
        #expect(s.load(Sample.self, key: "k") == nil)
        s.save(Sample(a: 1, b: "x"), key: "k")
        #expect(s.load(Sample.self, key: "k") == Sample(a: 1, b: "x"))
        let scoped = s.scoped("p.")
        scoped.save(Sample(a: 2, b: "y"), key: "k")
        #expect(s.load(Sample.self, key: "k") == Sample(a: 1, b: "x"))
        #expect(s.load(Sample.self, key: "p.k") == Sample(a: 2, b: "y"))
    }

    @Test func settingsBoxPersists() {
        let d = UserDefaults(suiteName: "ergo.test.\(UUID().uuidString)")!
        let s = SettingsStore(defaults: d)
        let box = SettingsBox(store: s, key: "box", default: Sample(a: 0, b: ""))
        box.value.a = 42
        let again = SettingsBox(store: s, key: "box", default: Sample(a: 0, b: ""))
        #expect(again.value.a == 42)
    }
}

@Suite struct UsageStoreTests {
    @Test func boostGrowsAndCaps() {
        let u = UsageStore(url: nil)
        #expect(u.boost(itemID: "a", query: "sa") == 0)
        u.record(itemID: "a", query: "sa")
        let one = u.boost(itemID: "a", query: "sa")
        #expect(one > 0)
        for _ in 0..<50 { u.record(itemID: "a", query: "sa") }
        let many = u.boost(itemID: "a", query: "sa")
        #expect(many > one)
        #expect(many <= 0.2)
    }

    @Test func exactQueryBeatsOthers() {
        let u = UsageStore(url: nil)
        for _ in 0..<5 { u.record(itemID: "a", query: "saf") }
        #expect(u.boost(itemID: "a", query: "saf") > u.boost(itemID: "a", query: "zzz"))
        #expect(u.boost(itemID: "a", query: "sa") > u.boost(itemID: "a", query: "zzz"))
    }

    @Test func persistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let u = UsageStore(url: url)
        u.record(itemID: "x", query: "q")
        try await Task.sleep(for: .milliseconds(300))
        let u2 = UsageStore(url: url)
        #expect(u2.boost(itemID: "x", query: "q") > 0)
    }
}

@Suite struct SecretStoreTests {
    @Test func setGetDelete() throws {
        let s = SecretStore(service: "com.jrainlau.ergo.test.\(UUID().uuidString)")
        #expect(s.secret("acct") == nil)
        try s.setSecret("v1", account: "acct")
        #expect(s.secret("acct") == "v1")
        try s.setSecret("v2", account: "acct")
        #expect(s.secret("acct") == "v2")
        try s.setSecret(nil, account: "acct")
        #expect(s.secret("acct") == nil)
    }
}

@Suite struct DoubleTapDetectorTests {
    private func tap(_ d: inout DoubleTapDetector, code: UInt16, down: Double, up: Double, mod: ModifierSet = .control) -> ModifierKey? {
        _ = d.process(.flagsChanged(keyCode: code, flags: mod), at: down)
        return d.process(.flagsChanged(keyCode: code, flags: []), at: up)
    }

    @Test func detectsDoubleTap() {
        var d = DoubleTapDetector(interval: 0.3)
        #expect(tap(&d, code: 59, down: 0.00, up: 0.08) == nil)
        #expect(tap(&d, code: 59, down: 0.20, up: 0.27) == .control)
    }

    @Test func tooSlow() {
        var d = DoubleTapDetector(interval: 0.3)
        #expect(tap(&d, code: 59, down: 0.0, up: 0.08) == nil)
        #expect(tap(&d, code: 59, down: 0.9, up: 0.97) == nil)
    }

    @Test func longPressIgnored() {
        var d = DoubleTapDetector()
        #expect(tap(&d, code: 59, down: 0, up: 0.6) == nil)
        #expect(tap(&d, code: 59, down: 0.7, up: 0.75) == nil)
    }

    @Test func otherKeyResets() {
        var d = DoubleTapDetector()
        _ = tap(&d, code: 59, down: 0, up: 0.05)
        _ = d.process(.otherInput, at: 0.1)
        #expect(tap(&d, code: 59, down: 0.15, up: 0.2) == nil)
    }

    @Test func combinedWithOtherModifierIgnored() {
        var d = DoubleTapDetector()
        _ = tap(&d, code: 59, down: 0, up: 0.05)
        _ = d.process(.flagsChanged(keyCode: 59, flags: [.control, .command]), at: 0.1)
        #expect(d.process(.flagsChanged(keyCode: 59, flags: []), at: 0.15) == nil)
    }

    @Test func differentKeysDoNotCombine() {
        var d = DoubleTapDetector()
        _ = tap(&d, code: 59, down: 0, up: 0.05)
        #expect(tap(&d, code: 58, down: 0.1, up: 0.15, mod: .option) == nil)
    }

    @Test func rightKeyAlsoWorks() {
        var d = DoubleTapDetector()
        _ = tap(&d, code: 61, down: 0, up: 0.05, mod: .option)
        #expect(tap(&d, code: 61, down: 0.1, up: 0.15, mod: .option) == .option)
    }

    @Test func tripleTapFiresOnceThenRestarts() {
        var d = DoubleTapDetector()
        _ = tap(&d, code: 59, down: 0, up: 0.05)
        #expect(tap(&d, code: 59, down: 0.1, up: 0.15) == .control)
        #expect(tap(&d, code: 59, down: 0.2, up: 0.25) == nil)
    }
}
