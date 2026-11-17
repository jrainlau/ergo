import AppKit
import ErgoPluginSupport
import ErgoUI
import SwiftUI

struct ClipPreviewView: View {
    let item: ClipItem
    let store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: String {
        var parts = ["复制于 " + FormatHelpers.relativeDateTime(Date(timeIntervalSince1970: item.lastCopiedAt))]
        if let app = item.sourceAppName { parts.append("来自 \(app)") }
        if item.copyCount > 1 { parts.append("共 \(item.copyCount) 次") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        switch item.clipKind {
        case .text:
            TextPreview(text: item.textContent ?? item.title)
        case .richText:
            if let url = store.blobURL(item), let data = try? Data(contentsOf: url),
               let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                VStack(alignment: .leading) {
                    RichTextView(attributed: attr)
                    Text("\((item.textContent ?? "").count) 个字符").font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                TextPreview(text: item.textContent ?? item.title)
            }
        case .link:
            LinkPreview(text: item.textContent ?? item.title)
        case .image:
            ImagePreview(url: store.blobURL(item) ?? store.thumbURL(item), meta: item.meta)
        case .file:
            FilePreview(item: item, store: store)
        case .color:
            ColorPreview(hex: item.meta.colorHex ?? item.title)
        }
    }
}

struct TextPreview: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                Text(text.count > 20_000 ? String(text.prefix(20_000)) + "…" : text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            Text("\(text.count) 个字符 · \(lines) 行").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct RichTextView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        if let tv = sv.documentView as? NSTextView {
            tv.isEditable = false
            tv.drawsBackground = false
            tv.textContainerInset = .zero
            tv.textStorage?.setAttributedString(attributed)
        }
        sv.drawsBackground = false
        sv.hasHorizontalScroller = false
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        (sv.documentView as? NSTextView)?.textStorage?.setAttributedString(attributed)
    }
}

struct LinkPreview: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "link").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "").font(.title3.weight(.medium))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("在浏览器打开") { NSWorkspace.shared.open(url) }
            }
            Spacer()
        }
    }
}

struct ImagePreview: View {
    let url: URL?
    let meta: ClipMeta
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let w = meta.pixelWidth, let h = meta.pixelHeight {
                Text("\(w)×\(h)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = ImageTools.downsampledImage(at: url, maxPixel: 1200)
        }
    }
}

struct FilePreview: View {
    let item: ClipItem
    let store: ClipboardStore

    var body: some View {
        let paths = item.meta.paths ?? []
        let first = paths.first.map { URL(fileURLWithPath: $0) }
        VStack(alignment: .leading, spacing: 8) {
            if let first {
                HStack(spacing: 8) {
                    Image(nsImage: IconCache.shared.icon(for: first, size: 28)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(paths.count == 1 ? first.lastPathComponent : "\(paths.count) 个文件").font(.system(size: 13, weight: .medium))
                        Text(first.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if paths.count == 1 {
                    if FileManager.default.fileExists(atPath: first.path) {
                        QuickLookPreview(url: first)
                    } else if let blob = store.blobURL(item) {
                        QuickLookPreview(url: blob)
                    } else {
                        Label("文件已不存在", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(paths, id: \.self) { p in
                                Text((p as NSString).lastPathComponent).font(.system(size: 12)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct ColorPreview: View {
    let hex: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: ClipColor.color(fromHex: hex) ?? .gray))
                .frame(height: 120)
            Text(hex).font(.system(size: 18, weight: .medium, design: .monospaced)).textSelection(.enabled)
            if let c = ClipColor.color(fromHex: hex)?.usingColorSpace(.sRGB) {
                Text("RGB \(Int(round(c.redComponent * 255))), \(Int(round(c.greenComponent * 255))), \(Int(round(c.blueComponent * 255)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

enum ClipColor {
    static func color(fromHex hex: String) -> NSColor? {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
