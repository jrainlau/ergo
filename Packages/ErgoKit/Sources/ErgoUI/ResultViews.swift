import ErgoPluginKit
import SwiftUI

public struct ResultIconView: View {
    let icon: ResultIcon
    let size: CGFloat

    public init(icon: ResultIcon, size: CGFloat = 32) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        case .fileIcon(let url), .appIcon(let url):
            Image(nsImage: IconCache.shared.icon(for: url, size: size))
                .resizable().frame(width: size, height: size)
        case .image(let img):
            Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
        case .bundleAppIcon(let id):
            if let img = IconCache.shared.icon(bundleID: id, size: size) {
                Image(nsImage: img).resizable().frame(width: size, height: size)
            } else {
                Image(systemName: "app.dashed").font(.system(size: size * 0.6))
                    .foregroundStyle(.secondary).frame(width: size, height: size)
            }
        }
    }
}

public struct ResultRowView: View {
    let item: ResultItem
    let hint: String?
    let isSelected: Bool

    public init(item: ResultItem, hint: String?, isSelected: Bool) {
        self.item = item
        self.hint = hint
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: 12) {
            ResultIconView(icon: item.icon, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let acc = item.accessoryText {
                Text(acc).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.title, item.subtitle].compactMap { $0 }.joined(separator: "，"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
