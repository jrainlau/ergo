import Foundation

public enum Permission: String, Sendable, Codable, CaseIterable, Hashable {
    case accessibility, inputMonitoring, fullDiskAccess, pasteboard, screenRecording

    public var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .inputMonitoring: "输入监控"
        case .fullDiskAccess: "完全磁盘访问"
        case .pasteboard: "剪贴板读取"
        case .screenRecording: "屏幕录制"
        }
    }

    public var detail: String {
        switch self {
        case .accessibility: "用于向前台应用模拟 ⌘V 粘贴"
        case .inputMonitoring: "用于监听“双击修饰键”快捷键"
        case .fullDiskAccess: "可选，用于搜索受保护的目录"
        case .pasteboard: "用于记录剪贴板历史"
        case .screenRecording: "用于截图与录屏"
        }
    }
}

public enum PermissionStatus: Sendable {
    case granted, denied, notDetermined, unknown
}

public struct PermissionRequirement: Sendable {
    public var permission: Permission
    public var reason: String
    public var isRequired: Bool
    public init(permission: Permission, reason: String, isRequired: Bool = true) {
        self.permission = permission
        self.reason = reason
        self.isRequired = isRequired
    }
}
