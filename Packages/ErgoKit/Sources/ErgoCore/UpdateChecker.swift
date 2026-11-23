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
        case .http(let code): "服务器返回 HTTP \(code)"
        case .missingChecksum: "发布页没有提供校验值，已放弃自动安装"
        case .checksumMismatch: "安装包校验失败（sha256 不一致），已丢弃"
        case .badPackage(let why): "安装包无效：\(why)"
        case .commandFailed(let why): "命令执行失败：\(why)"
        }
    }
}

public nonisolated enum UpdateChecker {
    public static let repo = "jrainlau/ergo"
    public static let releasesURL = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!

    public static func fetchReleases(session: URLSession = .shared) async throws -> [GitHubRelease] {
        var request = URLRequest(url: releasesURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ergo-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    /// 在所有 Release 中挑出版本号最大、且高于当前版本的那个。
    /// 按版本号而不是发布时间排序：GitHub 返回顺序可能与版本顺序不一致。
    public static func pickUpdate(from releases: [GitHubRelease], current: AppVersion, includePrereleases: Bool) -> UpdateInfo? {
        var best: (AppVersion, GitHubRelease, GitHubRelease.Asset)?
        for r in releases where !r.draft && (includePrereleases || !r.prerelease) {
            guard let v = AppVersion(r.tagName), v > current,
                  let dmg = r.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { continue }
            if best == nil || v > best!.0 { best = (v, r, dmg) }
        }
        guard let (v, r, dmg) = best else { return nil }
        let digest = dmg.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return UpdateInfo(
            version: v,
            isPrerelease: r.prerelease,
            notes: r.body ?? "",
            pageURL: r.htmlURL,
            dmgName: dmg.name,
            dmgURL: dmg.browserDownloadURL,
            dmgSize: dmg.size,
            sha256: digest?.lowercased(),
            checksumFileURL: r.assets.first(where: { $0.name == dmg.name + ".sha256" })?.browserDownloadURL
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
