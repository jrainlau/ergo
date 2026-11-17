import Foundation
import Testing
@testable import PluginCurrency

private let codes: Set<String> = ["USD", "CNY", "EUR", "JPY", "GBP", "HKD", "KRW"]
private func p(_ s: String, yen: Bool = false) -> ParsedCurrencyQuery? { CurrencyQueryParser.parse(s, knownCodes: codes, yenIsJPY: yen) }

@Suite struct CurrencyParserTests {
    @Test func symbolOnlyDefaultsToOne() {
        #expect(p("$") == ParsedCurrencyQuery(amount: 1, source: "USD", target: nil))
        #expect(p("¥") == ParsedCurrencyQuery(amount: 1, source: "CNY", target: nil))
        #expect(p("¥", yen: true)?.source == "JPY")
    }

    @Test func symbolWithAmount() {
        #expect(p("$100") == ParsedCurrencyQuery(amount: 100, source: "USD", target: nil))
        #expect(p("¥ 100*3")?.amount == 300)
        #expect(p("€50")?.source == "EUR")
        #expect(p("£2.5")?.amount == 2.5)
        #expect(p("hk$20") == ParsedCurrencyQuery(amount: 20, source: "HKD", target: nil))
        #expect(p("₩1000")?.source == "KRW")
    }

    @Test func amountWithUnit() {
        #expect(p("100usd") == ParsedCurrencyQuery(amount: 100, source: "USD", target: nil))
        #expect(p("100 USD")?.source == "USD")
        #expect(p("100 美元")?.source == "USD")
        #expect(p("12.5 人民币")?.source == "CNY")
        #expect(p("3*4 eur")?.amount == 12)
        #expect(p("100 日元")?.source == "JPY")
    }

    @Test func explicitTarget() {
        #expect(p("100 usd to jpy") == ParsedCurrencyQuery(amount: 100, source: "USD", target: "JPY"))
        #expect(p("100 美元 转 人民币") == ParsedCurrencyQuery(amount: 100, source: "USD", target: "CNY"))
        #expect(p("100usd in eur")?.target == "EUR")
        #expect(p("50 eur = gbp")?.target == "GBP")
        #expect(p("$100 to cny") == ParsedCurrencyQuery(amount: 100, source: "USD", target: "CNY"))
        #expect(p("100 美元兑换日元")?.target == "JPY")
    }

    @Test func rejectsNonCurrency() {
        #expect(p("") == nil)
        #expect(p("100") == nil)
        #expect(p("abc") == nil)
        #expect(p("1+1") == nil)
        #expect(p("100 xyz") == nil)
        #expect(p("100 usd to xyz") == nil)
        #expect(p("100 usd foo") == nil)
        #expect(p("$abc") == nil)
    }

    @Test func unknownCodeRejectedWhenNotInTable() {
        #expect(CurrencyQueryParser.parse("100 chf", knownCodes: codes) == nil)
        #expect(CurrencyQueryParser.parse("100 chf", knownCodes: codes.union(["CHF"]))?.source == "CHF")
    }
}

@Suite struct RateTableTests {
    let table = RateTable(base: "USD", rates: ["USD": 1, "CNY": 7.2, "EUR": 0.9, "JPY": 150], sourceDate: "2026-01-01", fetchedAt: Date(), providerName: "t")

    @Test func convertViaBase() {
        #expect(table.convert(100, from: "USD", to: "CNY") == 720)
        let eurToCny = table.convert(10, from: "EUR", to: "CNY")!
        #expect(abs(eurToCny - 80) < 1e-9)
        #expect(table.convert(1, from: "USD", to: "XXX") == nil)
    }

    @Test func formatting() {
        #expect(CurrencyFormat.plain(1234.5678, code: "USD") == "1234.57")
        #expect(CurrencyFormat.plain(1234.5678, code: "JPY") == "1235")
        #expect(CurrencyFormat.flag("USD") == "🇺🇸")
        #expect(CurrencyFormat.flag("EUR") == "🇪🇺")
        #expect(CurrencyFormat.display(1234.5, code: "CNY").contains("1,234.50"))
    }

    @Test func parseFrankfurter() throws {
        let json = #"{"amount":1.0,"base":"USD","date":"2026-01-02","rates":{"CNY":7.1,"EUR":0.92}}"#
        let t = try RateProviders.parseFrankfurter(Data(json.utf8))
        #expect(t.rates["USD"] == 1)
        #expect(t.rates["CNY"] == 7.1)
        #expect(t.sourceDate == "2026-01-02")
    }

    @Test func parseOpenER() throws {
        let json = #"{"result":"success","time_last_update_unix":1767225600,"rates":{"USD":1,"CNY":7.0}}"#
        let t = try RateProviders.parseOpenER(Data(json.utf8))
        #expect(t.rates["CNY"] == 7.0)
        #expect(t.sourceDate == "2026-01-01")
        #expect(throws: RateProviderError.self) { try RateProviders.parseOpenER(Data(#"{"result":"error","rates":{}}"#.utf8)) }
        #expect(throws: RateProviderError.self) { try RateProviders.parseFrankfurter(Data("nope".utf8)) }
    }

    @Test func tableCodableRoundTrip() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        let t = RateTable(base: "USD", rates: ["USD": 1], sourceDate: "x", fetchedAt: Date(timeIntervalSince1970: 1000), providerName: "p")
        #expect(try dec.decode(RateTable.self, from: enc.encode(t)) == t)
    }
}
