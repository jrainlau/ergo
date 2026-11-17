import AppKit
import CryptoKit
import ErgoPluginSupport
import Foundation
import UniformTypeIdentifiers

/// 在主线程从 NSPasteboard 读出的原始数据（Sendable，可交给后台处理）。
public nonisolated struct RawCapture: Sendable {
    var fileURLs: [URL] = []
    var imageData: Data?
    var colorHex: String?
    var rtf: Data?
    var string: String?
    var sourceBundleID: String?
    var sourceAppName: String?
}

public nonisolated struct ClipFilter: Sendable {
    var text = true, richText = true, image = true, file = true, color = true
    var imageCopyLimitBytes: Int64 = 20 * 1024 * 1024
}

/// 分类结果（尚未写盘）。
public nonisolated struct Classified: Sendable {
    var kind: ClipKind
    var hash: String
    var title: String
    var text: String?
    var meta: ClipMeta
    var imageData: Data?     // 统一为 PNG
    var rtf: Data?
    var sourceBundleID: String?
    var sourceAppName: String?
}

public nonisolated enum ClipboardProcessor {
    static let maxStoredText = 200_000

    public static func classify(_ raw: RawCapture, filter: ClipFilter) -> Classified? {
        // 1. 文件
        if !raw.fileURLs.isEmpty {
            guard filter.file else { return nil }
            return classifyFiles(raw)
        }
        // 2. 图片
        if let data = raw.imageData {
            guard filter.image, let png = ImageTools.pngData(from: data) else { return nil }
            let size = ImageTools.pixelSize(of: png)
            var meta = ClipMeta()
            meta.pixelWidth = size?.width
            meta.pixelHeight = size?.height
            meta.byteSize = Int64(png.count)
            let w = size?.width ?? 0, h = size?.height ?? 0
            return Classified(
                kind: .image, hash: sha256(png),
                title: "图片: \(w)×\(h) (\(FormatHelpers.byteCount(Int64(png.count))))",
                text: nil, meta: meta, imageData: png, rtf: nil,
                sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName
            )
        }
        // 3. 颜色
        if let hex = raw.colorHex {
            guard filter.color else { return nil }
            var meta = ClipMeta()
            meta.colorHex = hex
            return Classified(kind: .color, hash: sha256(Data("color:\(hex)".utf8)), title: hex, text: hex, meta: meta, imageData: nil, rtf: nil, sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName)
        }
        guard let str = raw.string, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let stored = str.count > maxStoredText ? String(str.prefix(maxStoredText)) : str
        // 4. 富文本
        if let rtf = raw.rtf {
            guard filter.richText else { return nil }
            return Classified(kind: .richText, hash: sha256(Data(("rtf:" + stored).utf8)), title: title(forText: stored), text: stored, meta: ClipMeta(), imageData: nil, rtf: rtf, sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName)
        }
        guard filter.text else { return nil }
        // 5. 链接
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLink(trimmed) {
            return Classified(kind: .link, hash: sha256(Data(("text:" + stored).utf8)), title: trimmed, text: stored, meta: ClipMeta(), imageData: nil, rtf: nil, sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName)
        }
        // 6. 文本
        return Classified(kind: .text, hash: sha256(Data(("text:" + stored).utf8)), title: title(forText: stored), text: stored, meta: ClipMeta(), imageData: nil, rtf: nil, sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName)
    }

    static func classifyFiles(_ raw: RawCapture) -> Classified {
        let urls = raw.fileURLs
        var meta = ClipMeta()
        meta.fileCount = urls.count
        meta.paths = urls.map(\.path)
        var title: String
        if urls.count == 1, let u = urls.first {
            title = "文件: \(u.lastPathComponent)"
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                meta.fileCategory = "folder"
            } else if let t = UTType(filenameExtension: u.pathExtension) {
                if t.conforms(to: .image) { meta.fileCategory = "image" }
                else if t.conforms(to: .movie) { meta.fileCategory = "movie" }
                else if t.conforms(to: .audio) { meta.fileCategory = "audio" }
                else { meta.fileCategory = "other" }
            } else {
                meta.fileCategory = "other"
            }
            if let size = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize { meta.byteSize = Int64(size) }
        } else {
            title = "\(urls.count) 个文件"
            meta.fileCategory = "other"
        }
        let hash = sha256(Data(("files:" + urls.map(\.path).joined(separator: "\n")).utf8))
        return Classified(kind: .file, hash: hash, title: title, text: urls.map(\.path).joined(separator: "\n"), meta: meta, imageData: nil, rtf: nil, sourceBundleID: raw.sourceBundleID, sourceAppName: raw.sourceAppName)
    }

    /// 为已确认是新记录的内容写入 blob / 缩略图，并生成数据库记录。
    public static func makeItem(from c: Classified, blobsDir: URL, thumbsDir: URL, filter: ClipFilter, now: Date = Date()) -> ClipItem {
        let id = UUID().uuidString
        var blob: String?
        var thumb: String?
        let fm = FileManager.default

        switch c.kind {
        case .image:
            if let png = c.imageData {
                blob = id + ".png"
                try? png.write(to: blobsDir.appendingPathComponent(blob!))
                if let t = ImageTools.thumbnailPNG(from: png, maxPixel: 512) {
                    thumb = id + ".png"
                    try? t.write(to: thumbsDir.appendingPathComponent(thumb!))
                }
            }
        case .richText:
            if let rtf = c.rtf {
                blob = id + ".rtf"
                try? rtf.write(to: blobsDir.appendingPathComponent(blob!))
            }
        case .file:
            if c.meta.fileCount == 1, let p = c.meta.paths?.first, c.meta.fileCategory == "image" {
                let u = URL(fileURLWithPath: p)
                if let t = ImageTools.thumbnailPNG(fromFile: u, maxPixel: 512) {
                    thumb = id + ".png"
                    try? t.write(to: thumbsDir.appendingPathComponent(thumb!))
                }
                if (c.meta.byteSize ?? 0) <= filter.imageCopyLimitBytes {
                    let ext = u.pathExtension.isEmpty ? "img" : u.pathExtension
                    blob = id + "." + ext
                    try? fm.copyItem(at: u, to: blobsDir.appendingPathComponent(blob!))
                }
            }
        default:
            break
        }

        let metaJSON = (try? JSONEncoder().encode(c.meta)).flatMap { String(data: $0, encoding: .utf8) }
        let t = now.timeIntervalSince1970
        return ClipItem(
            id: id, kind: c.kind.rawValue, title: c.title, textContent: c.text,
            blobPath: blob, thumbPath: thumb, metaJSON: metaJSON, contentHash: c.hash,
            sourceBundleID: c.sourceBundleID, sourceAppName: c.sourceAppName,
            createdAt: t, lastCopiedAt: t, copyCount: 1, isPinned: false
        )
    }

    // MARK: - 工具

    public static func title(forText s: String) -> String {
        let firstLine = s.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? Substring(s)
        let collapsed = firstLine.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.count > 200 ? String(collapsed.prefix(200)) : collapsed
    }

    public static func isLink(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace), let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && u.host != nil
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
