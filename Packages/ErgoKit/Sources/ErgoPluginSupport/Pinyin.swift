import Foundation

public enum Pinyin {
    public struct Result: Sendable, Equatable {
        public var full: String
        public var initials: String
        public var hasCJK: Bool
    }

    public static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    public static func convert(_ text: String) -> Result {
        var full = ""
        var initials = ""
        var hasCJK = false
        for ch in text {
            if let sc = ch.unicodeScalars.first, ch.unicodeScalars.count == 1, isCJK(sc) {
                hasCJK = true
                let s = String(ch)
                let latin = s.applyingTransform(.mandarinToLatin, reverse: false)?
                    .applyingTransform(.stripDiacritics, reverse: false)?
                    .lowercased() ?? ""
                let syllable = latin.filter { $0.isLetter }
                full += syllable
                if let f = syllable.first { initials.append(f) }
            } else if ch.isLetter || ch.isNumber {
                let lower = String(ch).lowercased()
                full += lower
                initials += lower
            }
        }
        return Result(full: full, initials: initials, hasCJK: hasCJK)
    }
}
