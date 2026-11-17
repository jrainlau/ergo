import Testing
@testable import PluginCalculator

@Suite struct CalculatorProviderTests {
    @Test(arguments: ["1+1", "2*3", "sqrt(16)", "=5", "(1+2)*3", "10/4", "2^10", "5!", "1 + 2", "２＋３", "3sqrt(4)", "2(3+4)"])
    func accepts(_ s: String) {
        #expect(CalculatorProvider.looksLikeExpression(s))
    }

    @Test(arguments: ["", "safari", "123", "1password", "7zip", "wx", "chrome", "pi", "=", "hello world"])
    func rejects(_ s: String) {
        #expect(!CalculatorProvider.looksLikeExpression(s))
    }
}
