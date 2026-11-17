import Foundation
import ErgoPluginKit

/// 基于 UserDefaults + JSON 的设置存储。
public final class SettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: prefix + key)
    }

    public func remove(key: String) {
        defaults.removeObject(forKey: prefix + key)
    }

    /// 给插件使用的带命名空间的子存储。
    public func scoped(_ namespace: String) -> SettingsStore {
        SettingsStore(defaults: defaults, prefix: prefix + namespace)
    }
}
