import Foundation

/// 严格的 x.y.z 版本号（与发布流程的 tag 约定一致，不带 v 前缀；这里也容忍 v 前缀）。
public nonisolated struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        major = a; minor = b; patch = c
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (l: AppVersion, r: AppVersion) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }
}

/// GitHub Releases API 返回里用到的字段。
public nonisolated struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let size: Int
        public let browserDownloadURL: URL
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }

        public init(name: String, size: Int, browserDownloadURL: URL, digest: String? = nil) {
            self.name = name
            self.size = size
            self.browserDownloadURL = browserDownloadURL
            self.digest = digest
        }
    }

    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let body: String?
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public init(tagName: String, draft: Bool = false, prerelease: Bool = false, body: String? = nil, htmlURL: URL, assets: [Asset]) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.body = body
        self.htmlURL = htmlURL
        self.assets = assets
    }
}

/// 一个可安装的新版本。
public nonisolated struct UpdateInfo: Equatable, Sendable {
    public let version: AppVersion
    public let isPrerelease: Bool
    public let notes: String
    public let pageURL: URL
    public let dmgName: String
    public let dmgURL: URL
    public let dmgSize: Int
    /// 来自 GitHub 为附件计算的 digest；缺失时用 `checksumFileURL` 兜底。
    public let sha256: String?
    public let checksumFileURL: URL?
}

public nonisolated struct UpdateSettingsData: Codable, Equatable, Sendable {
    public var autoCheck: Bool = true
    public var includePrereleases: Bool = true
    public var lastCheck: Date? = nil

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoCheck = try c.decodeIfPresent(Bool.self, forKey: .autoCheck) ?? true
        includePrereleases = try c.decodeIfPresent(Bool.self, forKey: .includePrereleases) ?? true
        lastCheck = try c.decodeIfPresent(Date.self, forKey: .lastCheck)
    }
}

public nonisolated enum UpdateError: LocalizedError {
    case http(Int)
    case missingChecksum
    case checksumMismatch
    case badPackage(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code) where code == 403 || code == 429: "GitHub 请求过于频繁（HTTP \(code)），请稍后再试"
        case .http(let code): "服务器返回 HTTP \(code)"
        case .missingChecksum: "发布页没有提供校验值，已放弃自动安装"
        case .checksumMismatch: "安装包校验失败（sha256 不一致），已丢弃"
        case .badPackage(let why): "安装包无效：\(why)"
        case .commandFailed(let why): "命令执行失败：\(why)"
        }
    }
}

/// versions.json 里的一条版本记录（由发布工作流生成）。
public nonisolated struct VersionEntry: Codable, Equatable, Sendable {
    public var version: String
    public var prerelease: Bool
    public var notes: String
    public var page: URL
    public var dmgName: String
    public var dmgURL: URL
    public var dmgSize: Int
    public var sha256: String?
    public var sha256URL: URL?

    enum CodingKeys: String, CodingKey {
        case version, prerelease, notes, page, sha256
        case dmgName = "dmg_name"
        case dmgURL = "dmg_url"
        case dmgSize = "dmg_size"
        case sha256URL = "sha256_url"
    }

    public init(version: String, prerelease: Bool, notes: String, page: URL, dmgName: String, dmgURL: URL, dmgSize: Int, sha256: String?, sha256URL: URL?) {
        self.version = version
        self.prerelease = prerelease
        self.notes = notes
        self.page = page
        self.dmgName = dmgName
        self.dmgURL = dmgURL
        self.dmgSize = dmgSize
        self.sha256 = sha256
        self.sha256URL = sha256URL
    }
}

public nonisolated enum UpdateChecker {
    public static let repo = "jrainlau/ergo"
    /// 首选：发布工作流维护的静态清单，走 CDN，不受 GitHub API 的 60 次/小时（按 IP）限流影响。
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/\(repo)/versions/versions.json")!
    /// 兜底：Releases API（未登录时按 IP 限流，容易 403）。
    public static let releasesURL = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!

    private static func get(_ url: URL, accept: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Ergo-Updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        return data
    }

    public static func fetchManifest(session: URLSession = .shared) async throws -> [VersionEntry] {
        let data = try await get(manifestURL, accept: "application/json", session: session)
        return try JSONDecoder().decode([VersionEntry].self, from: data)
    }

    public static func fetchReleases(session: URLSession = .shared) async throws -> [GitHubRelease] {
        let data = try await get(releasesURL, accept: "application/vnd.github+json", session: session)
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    /// 先读 versions.json，失败（尚未生成、网络问题等）再退回 Releases API。
    /// 两者都失败时抛出 API 的错误（通常更有信息量）。
    public static func findUpdate(current: AppVersion, includePrereleases: Bool, session: URLSession = .shared) async throws -> UpdateInfo? {
        if let entries = try? await fetchManifest(session: session), !entries.isEmpty {
            return pickUpdate(from: entries, current: current, includePrereleases: includePrereleases)
        }
        let releases = try await fetchReleases(session: session)
        return pickUpdate(from: releases, current: current, includePrereleases: includePrereleases)
    }

    public static func entries(from releases: [GitHubRelease]) -> [VersionEntry] {
        releases.compactMap { r in
            guard !r.draft, let dmg = r.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { return nil }
            let digest = dmg.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
            return VersionEntry(
                version: r.tagName, prerelease: r.prerelease, notes: r.body ?? "", page: r.htmlURL,
                dmgName: dmg.name, dmgURL: dmg.browserDownloadURL, dmgSize: dmg.size,
                sha256: digest?.lowercased(),
                sha256URL: r.assets.first(where: { $0.name == dmg.name + ".sha256" })?.browserDownloadURL
            )
        }
    }

    public static func pickUpdate(from releases: [GitHubRelease], current: AppVersion, includePrereleases: Bool) -> UpdateInfo? {
        pickUpdate(from: entries(from: releases), current: current, includePrereleases: includePrereleases)
    }

    /// 挑出版本号最大、且高于当前版本的那条。按版本号而不是列表顺序排序。
    public static func pickUpdate(from entries: [VersionEntry], current: AppVersion, includePrereleases: Bool) -> UpdateInfo? {
        var best: (AppVersion, VersionEntry)?
        for e in entries where includePrereleases || !e.prerelease {
            guard let v = AppVersion(e.version), v > current else { continue }
            if best == nil || v > best!.0 { best = (v, e) }
        }
        guard let (v, e) = best else { return nil }
        return UpdateInfo(
            version: v, isPrerelease: e.prerelease, notes: e.notes, pageURL: e.page,
            dmgName: e.dmgName, dmgURL: e.dmgURL, dmgSize: e.dmgSize,
            sha256: e.sha256?.lowercased(), checksumFileURL: e.sha256URL
        )
    }

    /// 取得期望的 sha256：优先用 API 里的 digest，否则读取 `.sha256` 附件。
    public static func expectedChecksum(for info: UpdateInfo, session: URLSession = .shared) async throws -> String {
        if let s = info.sha256, !s.isEmpty { return s }
        guard let url = info.checksumFileURL else { throw UpdateError.missingChecksum }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8), let hash = parseChecksumFile(text) else {
            throw UpdateError.missingChecksum
        }
        return hash
    }

    /// 解析 `shasum -a 256` 的输出：`<64 位十六进制>  <文件名>`。
    public static func parseChecksumFile(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let hash = first.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }
}

/// 设置页与更新服务之间的桥：服务填入回调并更新状态，设置页观察状态。
@Observable
public final class UpdateBridge {
    public var status: String = ""
    public var isBusy: Bool = false
    @ObservationIgnored public var onCheckNow: () -> Void = {}

    public init() {}
}
