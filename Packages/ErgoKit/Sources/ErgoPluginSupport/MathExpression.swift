import Foundation

/// 递归下降的数学表达式求值器（纯逻辑，线程安全）。
public struct MathExpression: Sendable {
    public enum EvalError: Error, Equatable {
        case syntax
        case domain
    }

    public static func evaluate(_ input: String, degrees: Bool = false) throws -> Double {
        var parser = Parser(text: normalize(input), degrees: degrees)
        let value = try parser.parseAll()
        guard value.isFinite else { throw EvalError.domain }
        return value
    }

    public static func normalize(_ input: String) -> String {
        var s = input.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input
        s = s.lowercased()
        let replacements: [(String, String)] = [
            ("×", "*"), ("✕", "*"), ("÷", "/"), ("（", "("), ("）", ")"),
            ("**", "^"), ("π", "pi"), ("，", ","), ("−", "-"),
        ]
        for (a, b) in replacements { s = s.replacingOccurrences(of: a, with: b) }
        s = s.filter { !$0.isWhitespace }
        if s.hasPrefix("=") { s.removeFirst() }
        return s
    }

    /// 原始数值字符串（无千分位），15 位有效数字。
    public static func rawString(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v == v.rounded(), abs(v) < 1e15 { return String(format: "%.0f", v) }
        var s = String(format: "%.15g", v)
        if s == "-0" { s = "0" }
        return s
    }

    /// 带千分位的展示字符串。
    public static func formatted(_ v: Double, maxSignificantDigits: Int = 15) -> String {
        let a = abs(v)
        if a != 0, a >= 1e15 || a < 1e-6 {
            return String(format: "%.10g", v)
        }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.usesSignificantDigits = true
        f.minimumSignificantDigits = 1
        f.maximumSignificantDigits = maxSignificantDigits
        return f.string(from: NSNumber(value: v)) ?? rawString(v)
    }

    // MARK: - Parser

    struct Parser {
        let chars: [Character]
        var i = 0
        let degrees: Bool

        init(text: String, degrees: Bool) {
            self.chars = Array(text)
            self.degrees = degrees
        }

        var peek: Character? { i < chars.count ? chars[i] : nil }

        mutating func parseAll() throws -> Double {
            guard !chars.isEmpty else { throw EvalError.syntax }
            let v = try parseExpr()
            guard i == chars.count else { throw EvalError.syntax }
            return v
        }

        mutating func parseExpr() throws -> Double {
            var v = try parseTerm()
            while let c = peek, c == "+" || c == "-" {
                i += 1
                let r = try parseTerm()
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        func startsWith(_ s: String) -> Bool {
            let a = Array(s)
            guard i + a.count <= chars.count else { return false }
            return Array(chars[i..<(i + a.count)]) == a
        }

        func beginsPrimary() -> Bool {
            guard let c = peek else { return false }
            if c.isNumber && c.isASCII { return true }
            if c == "(" { return true }
            if c.isLetter && c.isASCII { return !startsWith("mod") }
            return false
        }

        mutating func parseTerm() throws -> Double {
            var v = try parseUnary()
            while true {
                if let c = peek, c == "*" || c == "/" {
                    i += 1
                    let r = try parseUnary()
                    if c == "*" { v *= r } else {
                        guard r != 0 else { throw EvalError.domain }
                        v /= r
                    }
                } else if startsWith("mod") {
                    i += 3
                    let r = try parseUnary()
                    guard r != 0 else { throw EvalError.domain }
                    v = v.truncatingRemainder(dividingBy: r)
                } else if beginsPrimary() {
                    v *= try parseUnary()
                } else {
                    break
                }
            }
            return v
        }

        mutating func parseUnary() throws -> Double {
            if let c = peek, c == "+" || c == "-" {
                i += 1
                let v = try parseUnary()
                return c == "-" ? -v : v
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            let base = try parsePostfix()
            if peek == "^" {
                i += 1
                let exp = try parseUnary()
                let r = pow(base, exp)
                guard r.isFinite else { throw EvalError.domain }
                return r
            }
            return base
        }

        mutating func parsePostfix() throws -> Double {
            var v = try parsePrimary()
            while let c = peek, c == "%" || c == "!" {
                i += 1
                if c == "%" { v /= 100 } else {
                    guard v >= 0, v <= 170, v == v.rounded() else { throw EvalError.domain }
                    var f = 1.0
                    if v >= 2 { for k in 2...Int(v) { f *= Double(k) } }
                    v = f
                }
            }
            return v
        }

        mutating func parsePrimary() throws -> Double {
            guard let c = peek else { throw EvalError.syntax }
            if c == "(" {
                i += 1
                let v = try parseExpr()
                guard peek == ")" else { throw EvalError.syntax }
                i += 1
                return v
            }
            if c.isASCII && (c.isNumber || c == ".") { return try parseNumber() }
            if c.isASCII && c.isLetter { return try parseIdentifier() }
            throw EvalError.syntax
        }

        mutating func parseNumber() throws -> Double {
            if startsWith("0x") {
                i += 2
                let start = i
                while let c = peek, c.isHexDigit { i += 1 }
                guard i > start, let v = UInt64(String(chars[start..<i]), radix: 16) else { throw EvalError.syntax }
                return Double(v)
            }
            if startsWith("0b") {
                i += 2
                let start = i
                while let c = peek, c == "0" || c == "1" { i += 1 }
                guard i > start, let v = UInt64(String(chars[start..<i]), radix: 2) else { throw EvalError.syntax }
                return Double(v)
            }
            let start = i
            var seenDot = false
            while let c = peek, (c.isASCII && c.isNumber) || (c == "." && !seenDot) {
                if c == "." { seenDot = true }
                i += 1
            }
            // 科学计数法：e 后面紧跟数字（或 +/- 加数字）
            if peek == "e" {
                var j = i + 1
                if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                if j < chars.count, chars[j].isASCII, chars[j].isNumber {
                    i = j
                    while let c = peek, c.isASCII && c.isNumber { i += 1 }
                }
            }
            guard let v = Double(String(chars[start..<i])) else { throw EvalError.syntax }
            return v
        }

        mutating func parseIdentifier() throws -> Double {
            let start = i
            while let c = peek, c.isASCII && c.isLetter { i += 1 }
            var name = String(chars[start..<i])
            if name == "log", peek == "2" { i += 1; name = "log2" }
            switch name {
            case "pi": return Double.pi
            case "e": return M_E
            default: break
            }
            guard peek == "(" else { throw EvalError.syntax }
            i += 1
            var args: [Double] = [try parseExpr()]
            while peek == "," {
                i += 1
                args.append(try parseExpr())
            }
            guard peek == ")" else { throw EvalError.syntax }
            i += 1
            return try apply(name, args)
        }

        func apply(_ name: String, _ a: [Double]) throws -> Double {
            func one() throws -> Double {
                guard a.count == 1 else { throw EvalError.syntax }
                return a[0]
            }
            func two() throws -> (Double, Double) {
                guard a.count == 2 else { throw EvalError.syntax }
                return (a[0], a[1])
            }
            let toRad = degrees ? Double.pi / 180 : 1
            let fromRad = degrees ? 180 / Double.pi : 1
            switch name {
            case "sqrt": let x = try one(); guard x >= 0 else { throw EvalError.domain }; return x.squareRoot()
            case "cbrt": return cbrt(try one())
            case "abs": return abs(try one())
            case "sin": return sin(try one() * toRad)
            case "cos": return cos(try one() * toRad)
            case "tan": return tan(try one() * toRad)
            case "asin": let x = try one(); guard abs(x) <= 1 else { throw EvalError.domain }; return asin(x) * fromRad
            case "acos": let x = try one(); guard abs(x) <= 1 else { throw EvalError.domain }; return acos(x) * fromRad
            case "atan": return atan(try one()) * fromRad
            case "ln": let x = try one(); guard x > 0 else { throw EvalError.domain }; return log(x)
            case "log": let x = try one(); guard x > 0 else { throw EvalError.domain }; return log10(x)
            case "log2": let x = try one(); guard x > 0 else { throw EvalError.domain }; return log2(x)
            case "exp": return exp(try one())
            case "floor": return floor(try one())
            case "ceil": return ceil(try one())
            case "round": return (try one()).rounded(.toNearestOrAwayFromZero)
            case "min": guard let m = a.min() else { throw EvalError.syntax }; return m
            case "max": guard let m = a.max() else { throw EvalError.syntax }; return m
            case "pow": let (x, y) = try two(); return pow(x, y)
            default: throw EvalError.syntax
            }
        }
    }
}
