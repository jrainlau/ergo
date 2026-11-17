import Foundation

public nonisolated struct RateTable: Codable, Equatable, Sendable {
    public var base: String
    public var rates: [String: Double]
    public var sourceDate: String
    public var fetchedAt: Date
    public var providerName: String

    public var codes: Set<String> { Set(rates.keys) }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let f = rates[from], let t = rates[to], f > 0 else { return nil }
        return amount * t / f
    }

    public func rate(from: String, to: String) -> Double? { convert(1, from: from, to: to) }
}

public nonisolated enum RateProviderKind: String, Codable, CaseIterable, Sendable {
    case frankfurter, openER

    public var title: String {
        switch self {
        case .frankfurter: "Frankfurter（欧洲央行）"
        case .openER: "ExchangeRate-API（open.er-api.com）"
        }
    }
}

public nonisolated enum RateProviderError: Error, LocalizedError {
    case badResponse, badPayload
    public var errorDescription: String? {
        switch self {
        case .badResponse: "汇率服务返回异常"
        case .badPayload: "汇率数据格式不正确"
        }
    }
}

public nonisolated enum RateProviders {
    public static func fetch(_ kind: RateProviderKind, session: URLSession = .shared) async throws -> RateTable {
        let url: URL
        switch kind {
        case .frankfurter: url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!
        case .openER: url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Ergo", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateProviderError.badResponse }
        switch kind {
        case .frankfurter: return try parseFrankfurter(data)
        case .openER: return try parseOpenER(data)
        }
    }

    public static func parseFrankfurter(_ data: Data, now: Date = Date()) throws -> RateTable {
        struct R: Decodable { var base: String; var date: String; var rates: [String: Double] }
        guard let r = try? JSONDecoder().decode(R.self, from: data), !r.rates.isEmpty else { throw RateProviderError.badPayload }
        var rates = r.rates
        rates[r.base] = 1
        return RateTable(base: r.base, rates: rates, sourceDate: r.date, fetchedAt: now, providerName: "Frankfurter · 欧洲央行")
    }

    public static func parseOpenER(_ data: Data, now: Date = Date()) throws -> RateTable {
        struct R: Decodable { var result: String; var time_last_update_unix: Double?; var rates: [String: Double] }
        guard let r = try? JSONDecoder().decode(R.self, from: data), r.result == "success", !r.rates.isEmpty else { throw RateProviderError.badPayload }
        var rates = r.rates
        rates["USD"] = 1
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let date = r.time_last_update_unix.map { f.string(from: Date(timeIntervalSince1970: $0)) } ?? f.string(from: now)
        return RateTable(base: "USD", rates: rates, sourceDate: date, fetchedAt: now, providerName: "ExchangeRate-API")
    }
}

public nonisolated enum CurrencyFormat {
    static let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "PYG", "IDR"]

    public static func decimals(for code: String) -> Int { zeroDecimal.contains(code) ? 0 : 2 }

    public static func flag(_ code: String) -> String {
        if code == "EUR" { return "🇪🇺" }
        let letters = code.prefix(2).uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "💱" }
        var s = ""
        for u in letters { s.unicodeScalars.append(Unicode.Scalar(0x1F1E6 + u.value - 65)!) }
        return s
    }

    public static func chineseName(_ code: String) -> String {
        Locale(identifier: "zh_CN").localizedString(forCurrencyCode: code) ?? code
    }

    /// 带币种符号与千分位。
    public static func display(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .currency
        f.currencyCode = code
        f.minimumFractionDigits = decimals(for: code)
        f.maximumFractionDigits = decimals(for: code)
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals(for: code))f %@", value, code)
    }

    /// 复制用：不带符号与千分位。
    public static func plain(_ value: Double, code: String) -> String {
        String(format: "%.\(decimals(for: code))f", value)
    }
}
