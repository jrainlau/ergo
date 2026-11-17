import Foundation

public enum FormatHelpers {
    /// "今天 09:15" / "昨天 09:15" / "11月5日 09:15"
    public static func relativeDateTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let t = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(t)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "昨天 \(t)"
        }
        let df = DateFormatter()
        df.dateFormat = "M月d日 HH:mm"
        return df.string(from: date)
    }

    public static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func abbreviatingHome(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
