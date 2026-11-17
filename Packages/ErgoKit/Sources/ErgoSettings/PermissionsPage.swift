import SwiftUI
import ErgoCore
import ErgoPluginKit

struct PermissionRowView: View {
    let permission: Permission
    let status: PermissionStatus
    let usedBy: [String]
    let services: CoreServices

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.detail).font(.caption).foregroundStyle(.secondary)
                if !usedBy.isEmpty {
                    Text("使用方：" + usedBy.joined(separator: "、")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(label).font(.caption).foregroundStyle(.secondary)
            if status != .granted {
                Button("授权") { services.permissions.request(permission) }
            }
            Button("打开系统设置") { services.permissions.openSystemSettings(for: permission) }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .granted: .green
        case .denied: .red
        case .notDetermined: .orange
        case .unknown: .gray
        }
    }

    private var label: String {
        switch status {
        case .granted: "已授权"
        case .denied: "未授权"
        case .notDetermined: "需确认"
        case .unknown: "未知"
        }
    }
}

struct PermissionsPage: View {
    let host: PluginHost
    let services: CoreServices

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                Section {
                    ForEach(Permission.allCases, id: \.self) { p in
                        PermissionRowView(
                            permission: p,
                            status: services.permissions.status(p),
                            usedBy: host.registrations.filter { $0.manifest.permissions.contains { $0.permission == p } }.map(\.manifest.name),
                            services: services
                        )
                    }
                } footer: {
                    Text("授予“输入监控”后通常需要重启 Ergo 才会生效。")
                }
                Section {
                    Button("重启 Ergo") { PermissionService.relaunch() }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("权限")
    }
}
