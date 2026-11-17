import Foundation
import Testing
@testable import ErgoPluginSupport

private func ev(_ s: String, degrees: Bool = false) throws -> Double {
    try MathExpression.evaluate(s, degrees: degrees)
}

@Suite struct MathExpressionTests {
    @Test(arguments: [
        ("1+1", 2.0), ("2*3+4", 10.0), ("2+3*4", 14.0), ("(2+3)*4", 20.0), ("10/4", 2.5),
        ("10-3-2", 5.0), ("2^3", 8.0), ("2^3^2", 512.0), ("-2^2", -4.0), ("2^-1", 0.5),
        ("--3", 3.0), ("+5", 5.0), ("5%", 0.05), ("200*10%", 20.0), ("50%+1", 1.5),
        ("5!", 120.0), ("0!", 1.0), ("10 mod 3", 1.0), ("7mod4", 3.0),
        ("0x1f", 31.0), ("0b101", 5.0), ("1e3", 1000.0), ("1.5e2", 150.0), (".5+.5", 1.0),
        ("2pi", 2 * Double.pi), ("2(3+4)", 14.0), ("(1+2)(3+4)", 21.0), ("3sqrt(16)", 12.0),
        ("sqrt(16)", 4.0), ("cbrt(27)", 3.0), ("abs(-3)", 3.0), ("ln(e)", 1.0),
        ("log(1000)", 3.0), ("log2(8)", 3.0), ("exp(0)", 1.0), ("floor(2.7)", 2.0),
        ("ceil(2.1)", 3.0), ("round(2.5)", 3.0), ("min(3,1,2)", 1.0), ("max(3,1,2)", 3.0),
        ("pow(2,10)", 1024.0), ("pi", Double.pi), ("e", M_E),
        ("=1+2", 3.0), ("1 + 2", 3.0), ("１＋２", 3.0), ("2×3", 6.0), ("8÷2", 4.0),
        ("（1+2）*3", 9.0), ("2**3", 8.0), ("π", Double.pi),
    ])
    func evaluatesValid(_ expr: String, _ expected: Double) throws {
        let v = try ev(expr)
        #expect(abs(v - expected) < 1e-9, "\(expr) => \(v)")
    }

    @Test(arguments: ["", "1+", "(1+2", "1+2)", "abc", "foo(3)", "1/0", "sqrt(-1)", "ln(0)", "2.5!", "171!", "1..2", "*3", "sqrt()", "asin(2)"])
    func rejectsInvalid(_ expr: String) {
        #expect(throws: (any Error).self) { try ev(expr) }
    }

    @Test func degrees() throws {
        #expect(abs(try ev("sin(90)", degrees: true) - 1) < 1e-12)
        #expect(abs(try ev("cos(180)", degrees: true) + 1) < 1e-12)
        #expect(abs(try ev("asin(1)", degrees: true) - 90) < 1e-9)
        #expect(abs(try ev("sin(pi/2)") - 1) < 1e-12)
    }

    @Test func formatting() {
        #expect(MathExpression.rawString(0.1 + 0.2) == "0.3")
        #expect(MathExpression.rawString(1234567) == "1234567")
        #expect(MathExpression.formatted(1234567) == "1,234,567")
        #expect(MathExpression.formatted(1234.5) == "1,234.5")
        #expect(MathExpression.formatted(0.1 + 0.2) == "0.3")
        #expect(MathExpression.rawString(-0.0) == "0")
    }
}
