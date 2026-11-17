import Foundation

public nonisolated struct ClipboardSettings: Codable, Equatable, Sendable {
    /// 0 表示永久保留
    public var retentionDays: Int = 30
    public var maxItems: Int = 5000
    public var recordText = true
    public var recordRichText = true
    public var recordImage = true
    public var recordFile = true
    public var recordColor = true
    public var imageCopyLimitMB: Int = 20
    public var ignoredBundleIDs: [String] = [
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.bitwarden.desktop",
    ]
    public var pollInterval: Double = 0.5
    public var showSnippetsEntry = true

    public init() {}

    var filter: ClipFilter {
        var f = ClipFilter()
        f.text = recordText
        f.richText = recordRichText
        f.image = recordImage
        f.file = recordFile
        f.color = recordColor
        f.imageCopyLimitBytes = Int64(imageCopyLimitMB) * 1024 * 1024
        return f
    }

    var retention: TimeInterval? { retentionDays > 0 ? TimeInterval(retentionDays) * 86400 : nil }
}
