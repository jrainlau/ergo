import AppKit
import CryptoKit
import ErgoCore
import OSLog

/// 应用内自动更新：定时轮询 GitHub Releases，下载并校验 DMG，退出后由独立脚本替换 .app 并重新启动。
@MainActor
final class UpdateService {
    /// 两次自动检查之间的最短间隔。
    static let checkInterval: TimeInterval = 6 * 3600

    private let services: CoreServices
    private let log = Logger(subsystem: ErgoPaths.bundleID, category: "update")
    private var timer: Timer?
    private var busy = false
    private var promptedVersions: Set<AppVersion> = []

    private var settings: SettingsBox<UpdateSettingsData> { services.updateSettings }
    private var bridge: UpdateBridge { services.updates }

    init(services: CoreServices) {
        self.services = services
        services.updates.onCheckNow = { [weak self] in self?.checkNow() }
    }

    static var currentVersion: AppVersion {
        let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return AppVersion(s) ?? AppVersion("0.0.0")!
    }

    /// 启动后稍等片刻做一次检查，之后每小时醒来一次，距上次检查满 6 小时才真正请求
    /// （这样睡眠唤醒后也能及时补查，且设置变化无需重建定时器）。
    func start() {
        #if !DEBUG
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.autoCheckIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoCheckIfDue() }
        }
        #endif
    }

    private func autoCheckIfDue() {
        guard settings.value.autoCheck, !busy else { return }
        if let last = settings.value.lastCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    func checkNow() {
        guard !busy else { return }
        Task { await check(userInitiated: true) }
    }

    // MARK: - 检查与下载

    private func setStatus(_ text: String, busy: Bool) {
        bridge.status = text
        bridge.isBusy = busy
    }

    private func check(userInitiated: Bool) async {
        busy = true
        defer { busy = false }
        setStatus("正在检查更新…", busy: true)
        do {
            let releases = try await UpdateChecker.fetchReleases()
            settings.value.lastCheck = Date()
            let current = Self.currentVersion
            guard let info = UpdateChecker.pickUpdate(from: releases, current: current, includePrereleases: settings.value.includePrereleases) else {
                setStatus("已是最新版本（\(current)）", busy: false)
                if userInitiated { alert("已是最新版本", "当前版本 \(current) 已是最新。") }
                return
            }
            log.info("update available: \(info.version.description)")
            if !userInitiated, promptedVersions.contains(info.version) {
                setStatus("发现新版本 \(info.version)", busy: false)
                return
            }
            setStatus("正在下载 \(info.version)…", busy: true)
            let dmg = try await download(info)
            setStatus("发现新版本 \(info.version)", busy: false)
            promptedVersions.insert(info.version)
            if confirmInstall(info, current: current) {
                setStatus("正在安装 \(info.version)…", busy: true)
                try await install(dmg: dmg, info: info)
            }
        } catch {
            log.error("update failed: \(error.localizedDescription)")
            setStatus("更新失败：\(error.localizedDescription)", busy: false)
            if userInitiated { alert("更新失败", error.localizedDescription) }
        }
    }

    private var workDir: URL {
        let d = ErgoPaths.caches.appendingPathComponent("updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 下载并校验；已有校验通过的缓存则直接复用。
    private func download(_ info: UpdateInfo) async throws -> URL {
        let expected = try await UpdateChecker.expectedChecksum(for: info)
        let target = workDir.appendingPathComponent(info.dmgName)
        if FileManager.default.fileExists(atPath: target.path), (try? await Self.sha256(of: target)) == expected {
            return target
        }
        let (tmp, response) = try await URLSession.shared.download(from: info.dmgURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        guard (try await Self.sha256(of: tmp)) == expected else {
            try? FileManager.default.removeItem(at: tmp)
            throw UpdateError.checksumMismatch
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        return target
    }

    private func confirmInstall(_ info: UpdateInfo, current: AppVersion) -> Bool {
        let a = NSAlert()
        a.messageText = "发现新版本 Ergo \(info.version)"
        var text = "当前版本 \(current)。新版本已下载并校验完成，更新后 Ergo 会自动重启。"
        let notes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n\n" + String(notes.prefix(500)) }
        a.informativeText = text
        a.addButton(withTitle: "更新并重启")
        a.addButton(withTitle: "稍后")
        NSApp.activate()
        return a.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "好")
        NSApp.activate()
        a.runModal()
    }

    // MARK: - 安装

    private func install(dmg: URL, info: UpdateInfo) async throws {
        let target = Bundle.main.bundleURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let installed = target.path.hasPrefix("/Applications/") || target.path.hasPrefix(home + "/Applications/")
        let parent = target.deletingLastPathComponent().path
        guard installed, FileManager.default.isWritableFile(atPath: parent) else {
            // 非标准位置（如开发构建）或没有写权限：不自动覆盖，交给用户手动安装。
            NSWorkspace.shared.open(dmg)
            alert("请手动安装", "当前位置无法自动替换，已打开安装包，请把 Ergo 拖进「应用程序」。")
            setStatus("请手动安装 \(info.version)", busy: false)
            return
        }

        let staging = workDir.appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let newApp = staging.appendingPathComponent("Ergo.app")
        try await Self.extractApp(from: dmg, to: newApp, expectedVersion: info.version)

        let script = staging.appendingPathComponent("swap.sh")
        try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [
            "-c", #"nohup /bin/sh "$0" "$@" >/dev/null 2>&1 &"#,
            script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path, staging.path,
        ]
        try p.run()
        log.info("handing over to swap script, terminating")
        NSApp.terminate(nil)
    }

    /// 挂载 DMG，拷出 Ergo.app 并校验签名、Bundle ID 与版本号。
    @concurrent
    private static func extractApp(from dmg: URL, to dest: URL, expectedVersion: AppVersion) async throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            try? FileManager.default.removeItem(at: mount)
        }
        let src = mount.appendingPathComponent("Ergo.app")
        guard FileManager.default.fileExists(atPath: src.path) else { throw UpdateError.badPackage("DMG 里没有 Ergo.app") }
        _ = try run("/usr/bin/ditto", [src.path, dest.path])
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", dest.path])

        let plist = NSDictionary(contentsOf: dest.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == ErgoPaths.bundleID else { throw UpdateError.badPackage("Bundle ID 不匹配") }
        guard let v = plist?["CFBundleShortVersionString"] as? String, AppVersion(v) == expectedVersion else {
            throw UpdateError.badPackage("版本号与发布页不一致")
        }
    }

    /// 等旧进程退出 → 备份旧版并换入新版 → 去除隔离属性 → 重新启动；换入失败则回滚。
    private static let swapScript = """
    #!/bin/sh
    PID="$1"; TARGET="$2"; NEW="$3"; WORK="$4"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i+1)); done
    BACKUP="$TARGET.old"
    rm -rf "$BACKUP"
    if mv "$TARGET" "$BACKUP"; then
      if mv "$NEW" "$TARGET"; then
        rm -rf "$BACKUP"
      else
        mv "$BACKUP" "$TARGET"
      fi
    fi
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    open "$TARGET"
    rm -rf "$WORK"
    """

    private nonisolated static func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw UpdateError.commandFailed("\((exe as NSString).lastPathComponent): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }

    @concurrent
    private static func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
