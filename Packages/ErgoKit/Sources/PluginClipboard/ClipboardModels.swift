import Foundation
import GRDB

public nonisolated enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text, richText, link, image, file, color

    var symbol: String {
        switch self {
        case .text: "doc.text"
        case .richText: "doc.richtext"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

public nonisolated struct ClipMeta: Codable, Equatable, Sendable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteSize: Int64?
    var fileCount: Int?
    var paths: [String]?
    /// 文件类别：image / movie / audio / folder / other
    var fileCategory: String?
    var colorHex: String?
}

public nonisolated struct ClipItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "clip_item"

    public var id: String
    public var kind: String
    public var title: String
    public var textContent: String?
    public var blobPath: String?
    public var thumbPath: String?
    public var metaJSON: String?
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Double
    public var lastCopiedAt: Double
    public var copyCount: Int
    public var isPinned: Bool

    public var clipKind: ClipKind { ClipKind(rawValue: kind) ?? .text }

    public var meta: ClipMeta {
        guard let d = metaJSON?.data(using: .utf8), let m = try? JSONDecoder().decode(ClipMeta.self, from: d) else { return ClipMeta() }
        return m
    }
}
