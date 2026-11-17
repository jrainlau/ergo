# Ergo 插件开发指南

Ergo 的所有功能都是插件。内置的计算器、应用启动、文件搜索、汇率、剪贴板、常用语、AI 问答都用同一套接口写成，所以本文的内容也就是它们的写法。

> 本文以仓库里的实际代码为准，文中的示例代码都在当前 SDK 上编译通过。接口定义在 `Packages/ErgoKit/Sources/ErgoPluginKit/`，读不懂的地方直接看源码，不到 500 行。

## 目录

1. [基本概念](#1-基本概念)
2. [五分钟上手：新建一个插件](#2-五分钟上手新建一个插件)
3. [插件清单 `PluginManifest`](#3-插件清单-pluginmanifest)
4. [生命周期](#4-生命周期)
5. [搜索：`SearchProvider`](#5-搜索searchprovider)
6. [作用域：`PluginScope`](#6-作用域pluginscope)
7. [结果与动作：`ResultItem` / `ResultAction`](#7-结果与动作resultitem--resultaction)
8. [内联面板：`InlinePanel`](#8-内联面板inlinepanel)
9. [快捷键](#9-快捷键)
10. [宿主服务：`PluginContext`](#10-宿主服务plugincontext)
11. [设置与管理界面](#11-设置与管理界面)
12. [权限](#12-权限)
13. [可复用工具](#13-可复用工具)
14. [并发与线程约定](#14-并发与线程约定)
15. [测试](#15-测试)
16. [调试](#16-调试)
17. [常见问题](#17-常见问题)
18. [API 速查](#18-api-速查)

---

## 1. 基本概念

### 1.1 编译期插件

Ergo 的插件是**编译进应用的 SwiftPM target**，不是运行时加载的动态库。每个插件一个 target，位于 `Packages/ErgoKit/Sources/Plugin<Name>/`。

这样做的原因：个人自用的启动器不需要第三方分发，编译期插件没有签名、沙盒、ABI 兼容的麻烦，调试也和普通代码一样。代价是新增插件需要重新编译应用。

### 1.2 依赖规则（必须遵守）

```
插件  ──可以依赖──▶  ErgoPluginKit      协议与值类型（SDK 本体）
                     ErgoPluginSupport  可复用工具：模糊匹配、拼音、表达式求值、SSE、目录监听
                     ErgoUI             共享 SwiftUI / AppKit 组件
                     第三方库（GRDB、MarkdownUI 等）

插件  ──不能依赖──▶  ErgoCore、ErgoLauncher、ErgoSettings、ErgoAppCore（宿主）
                     其他插件
```

插件只通过 `PluginContext` 使用宿主能力，宿主通过 `ErgoPlugin` 协议调用插件。这个边界由 `Package.swift` 里的依赖声明保证：插件 target 的依赖只有上面几项，想偷偷 `import ErgoCore` 会直接编译失败。

### 1.3 一个插件由什么组成

| 部分 | 必需 | 作用 |
|---|---|---|
| `PluginManifest` | 是 | 静态描述：ID、名称、关键词、快捷键、权限 |
| `activate` / `deactivate` | 是 / 否 | 启用与停用时的资源创建与释放 |
| `searchProvider` | 否 | 参与主界面的全局搜索（输入什么都会问你一下） |
| `makeScope()` | 否 | 提供一个独立的“子界面”，通过关键词或快捷键进入 |
| `perform(hotkey:)` | 否 | 响应快捷键 |
| `makeSettingsView()` | 否 | 在设置里加几个设置项 |
| `makeManagementView()` | 否 | 提供一个较大的管理界面（如常用语的编辑器） |

一个插件可以同时有 searchProvider 和 scope：例如“常用语”输入 `sn` 进入作用域，也可以在设置里开启“参与全局搜索”。

---

## 2. 五分钟上手：新建一个插件

下面做一个“时间戳”插件：输入 `ts` 加空格进入作用域，输入时间戳得到日期，回车复制。

### 2.1 创建目录

```sh
cd Packages/ErgoKit/Sources
mkdir -p PluginTimestamp/Resources
printf '{\n  "sourceLanguage" : "zh-Hans",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' \
  > PluginTimestamp/Resources/Localizable.xcstrings
```

`Resources` 目录必须存在：`Package.swift` 里每个 target 都声明了 `resources: [.process("Resources")]`，目录缺失会导致 SwiftPM 报错。

### 2.2 写插件

`Sources/PluginTimestamp/TimestampPlugin.swift`：

```swift
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public nonisolated struct TimestampSettings: Codable, Equatable, Sendable {
    public var useMilliseconds = false
    public init() {}
}

public final class TimestampPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.timestamp", name: "时间戳",
            summary: "输入 ts 加时间戳，转换成日期；只输入 ts 得到当前时间戳",
            symbolName: "clock",
            keywords: [KeywordTrigger(text: "ts")],
            hotkeys: [HotkeyActionDescriptor(id: "timestamp.open", title: "唤起时间戳", defaultTrigger: .none)]
        )
    }

    private var context: (any PluginContext)?
    private var settings: SettingsBox<TimestampSettings>?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        settings = SettingsBox(store: context.settings, key: "main", default: TimestampSettings())
    }

    public func deactivate() async {
        context = nil
        settings = nil
    }

    public func makeScope() -> (any PluginScope)? {
        guard let context, let settings else { return nil }
        return TimestampScope(context: context, settings: settings)
    }

    public func perform(hotkey: HotkeyActionID) async {
        context?.launcher.show(scope: Self.manifest.id, query: nil)
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings else { return nil }
        return AnyView(TimestampSettingsView(settings: settings))
    }
}

struct TimestampSettingsView: View {
    @Bindable var settings: SettingsBox<TimestampSettings>

    var body: some View {
        Section("输出") {
            Toggle("使用毫秒", isOn: $settings.value.useMilliseconds)
        }
    }
}
```

`Sources/PluginTimestamp/TimestampScope.swift`：

```swift
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

@MainActor
final class TimestampScope: PluginScope {
    let title = "时间戳"
    let placeholder = "输入时间戳，例如 1700000000"
    let style: ScopeStyle = .list

    private let context: any PluginContext
    private let settings: SettingsBox<TimestampSettings>
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(context: any PluginContext, settings: SettingsBox<TimestampSettings>) {
        self.context = context
        self.settings = settings
    }

    func items(for query: SearchQuery) async throws -> [ResultItem] {
        let date: Date
        if query.text.isEmpty {
            date = Date()
        } else if let n = Double(query.text) {
            date = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
        } else {
            return []
        }
        let text = formatter.string(from: date)
        let seconds = date.timeIntervalSince1970
        let stamp = settings.value.useMilliseconds ? String(Int(seconds * 1000)) : String(Int(seconds))
        return [
            item(id: "date", title: text, subtitle: "日期", copy: text),
            item(id: "stamp", title: stamp, subtitle: "时间戳", copy: stamp),
        ]
    }

    private func item(id: String, title: String, subtitle: String, copy: String) -> ResultItem {
        let ctx = context
        return ResultItem(
            id: id, title: title, subtitle: subtitle,
            icon: .symbol("clock"),
            actions: [
                ResultAction(id: "copy", title: "复制") {
                    ctx.pasteboard.copy(.text(copy), marker: nil)
                    ctx.hud.show("已复制", symbol: "checkmark.circle")
                    return .hideLauncher
                },
                ResultAction(id: "paste", title: "粘贴到前台应用", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                    _ = await ctx.pasteboard.paste(.text(copy), marker: nil, restoreClipboard: true)
                    return .hideLauncher
                },
            ]
        )
    }
}
```

### 2.3 注册 target

在 `Packages/ErgoKit/Package.swift` 里加三处：

```swift
// 1. 插件 target（plugin() 会自动带上 ErgoPluginKit / ErgoPluginSupport / ErgoUI 和并发设置）
plugin("PluginTimestamp"),

// 2. 加进组合根的依赖列表
.target(
    name: "ErgoAppCore",
    dependencies: [
        // ...
        "PluginCurrency", "PluginSnippets", "PluginAIChat", "PluginTimestamp",
    ],
    // ...
),

// 3.（可选）测试 target
tests("PluginTimestampTests", ["PluginTimestamp", kit, support]),
```

需要第三方库时用 `plugin("PluginX", extra: [grdb, markdown])`，库的声明见 `Package.swift` 顶部。

### 2.4 加入目录

`Packages/ErgoKit/Sources/ErgoAppCore/PluginCatalog.swift`：

```swift
import PluginTimestamp   // 新增

enum PluginCatalog {
    static let all: [any ErgoPlugin.Type] = [
        // ...
        AIChatPlugin.self,
        TimestampPlugin.self,   // 新增
    ]
}
```

### 2.5 构建并试用

```sh
make build && ./scripts/run.sh
```

唤起 Ergo，输入 `ts 1700000000` 即可。在 设置 → 插件 里能看到新插件，可以启用、停用、修改关键词。

---

## 3. 插件清单 `PluginManifest`

```swift
PluginManifest(
    id: "ergo.timestamp",          // 全局唯一；建议 ergo.<名字> 或 <反域名>.<名字>
    name: "时间戳",                  // 设置里显示的名称，也是作用域标签
    summary: "一句话说明",
    symbolName: "clock",           // SF Symbol，用作插件图标
    version: "1.0.0",              // 默认 "1.0.0"
    permissions: [...],            // 见第 12 节
    keywords: [KeywordTrigger(text: "ts")],
    hotkeys: [HotkeyActionDescriptor(...)],
    enabledByDefault: true         // 默认 true
)
```

| 字段 | 说明 |
|---|---|
| `id` | **一旦发布不要改**。设置、数据目录、使用频率统计都以它为键 |
| `keywords` | 默认关键词。用户可在设置里增删改，运行时以用户设置为准。要求插件提供 `makeScope()`，否则关键词无效 |
| `KeywordTrigger.requiresSpace` | 默认 `true`：必须输入 `ts ` 才触发；`false` 时输入 `ts` 就触发 |
| `enabledByDefault` | 首次运行时是否启用 |

关键词冲突（两个插件用了同一个）时，先注册的生效，后者在设置里会看到冲突提示。

关键词匹配取**最长**的：同时有 `s` 和 `sn` 时，输入 `sn foo` 命中 `sn`。

---

## 4. 生命周期

```
应用启动
  └─ 对每个已启用的插件：init() → activate(context:)
        成功 → 状态 active；抛错 → 状态 failed(原因)，其他插件不受影响
用户在设置里停用 → deactivate()，实例被丢弃
用户重新启用     → 新建实例，再次 init() → activate(context:)
```

要点：

- `init()` 必须是空的且很快，不要在里面做事。真正的初始化放进 `activate`。
- `activate` 里创建数据库、文件监听、定时器等资源；`deactivate` 里**必须**释放它们（`invalidate` 定时器、`stop` 监听、关闭数据库）。
- `activate` 抛出的错误会显示在设置里该插件下方，同时记录日志。耗时的初始化应放到后台任务，不要阻塞启动。
- 每次启用都是一个**全新的实例**，不要依赖实例属性跨启用保留状态；要持久化就存设置或数据目录。
- 所有 `ErgoPlugin` 成员都在 `@MainActor` 上。

---

## 5. 搜索：`SearchProvider`

### 5.1 工作方式

用户每次输入，启动器按下面的顺序处理：

1. 如果输入以某个插件的关键词开头（且该插件有 `makeScope()`），**进入该插件的作用域**，不再走全局搜索。
2. 否则，对每个已启用插件的 `searchProvider` 调用 `canHandle(_:)`。
3. 返回 `true` 的 provider 并发执行 `search(_:)`，**每个最多 1.5 秒**，超时自动取消并视为无结果。
4. 结果按 `tier` 分组，组内按 `score × 0.8 + 使用频率加成` 排序。
5. `participation` 为 `.fallback` 的 provider 只在**所有 `.global` provider 都没有结果**时才运行，且最多显示 `maxItems` 条。

```swift
@MainActor
public protocol SearchProvider: AnyObject {
    var participation: SearchParticipation { get }
    var tier: ResultTier { get }
    func canHandle(_ query: SearchQuery) -> Bool          // 同步，必须 < 1ms
    func search(_ query: SearchQuery) async throws -> SearchOutput
}
```

### 5.2 `canHandle` 要快

`canHandle` 在每次按键时对所有插件同步调用，只做字符串层面的快速判断（前缀、字符集），不要查数据库、不要访问磁盘。真正耗时的工作放到 `search` 里。

计算器的做法：`canHandle` 里只检查“是否像算式”（有数字、有运算符、字符都合法），真正求值放在 `search`。

### 5.3 `SearchQuery`

| 属性 | 说明 |
|---|---|
| `raw` | 原始输入，保留首尾空格 |
| `text` | 去掉首尾空白 |
| `normalized` | `text` 的小写、去变音、全半角统一版本，用于匹配 |
| `sequence` | 递增序号，用于丢弃过期结果 |

比较关键词、做模糊匹配时用 `normalized`；展示给用户时用 `text`。

### 5.4 参与方式与层级

```swift
public enum SearchParticipation {
    case global                                          // 总是参与
    case fallback(maxItems: Int, minQueryLength: Int)    // 没有别的结果时才参与
    case none
}

public enum ResultTier: Int { case instant, primary, secondary, fallback }
```

`tier` 决定**分组顺序**（数字小的在前），不是分数。计算器用 `.instant`，所以 `1+1` 的结果永远在最上面；应用启动用 `.primary`；文件搜索的兜底结果用 `.fallback`。

### 5.5 返回值

```swift
public enum SearchOutput {
    case items([ResultItem])    // 普通结果列表
    case panel(InlinePanel)     // 内联面板（见第 8 节），例如汇率卡片
    case none
}
```

### 5.6 取消与过期

用户继续输入时，上一次的 `search` 所在 Task 会被取消。耗时的 `search` 应当在合适的位置检查 `Task.isCancelled` 或使用可取消的 API，避免白白消耗资源。宿主会丢弃 `sequence` 过期的结果，不需要你自己判断。

### 5.7 示例

一个最小的全局 provider：输入以 `hello` 开头时给出一条结果。

```swift
@MainActor
final class HelloProvider: SearchProvider {
    let participation: SearchParticipation = .global
    let tier: ResultTier = .secondary

    func canHandle(_ query: SearchQuery) -> Bool {
        query.normalized.hasPrefix("hello")
    }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        .items([
            ResultItem(
                id: "hello", title: "你好，Ergo", icon: .symbol("hand.wave"),
                actions: [ResultAction(id: "open", title: "好的") { .hideLauncher }]
            ),
        ])
    }
}
```

在插件类里暴露它：

```swift
private let provider = HelloProvider()
public var searchProvider: (any SearchProvider)? { provider }
```

---

## 6. 作用域：`PluginScope`

作用域是插件的“子界面”。进入后输入框左侧出现插件名标签，之后的输入全部交给该插件处理，Esc 或在空输入时按退格退出。

进入方式：

- 输入关键词（如 `ts `），余下部分作为作用域的初始查询；
- 插件自己调用 `context.launcher.show(scope: id, query:)`，通常是在快捷键回调里；
- 结果动作返回 `.openScope(id)`。

```swift
@MainActor
public protocol PluginScope: AnyObject {
    var title: String { get }
    var placeholder: String { get }          // 输入框占位文字
    var style: ScopeStyle { get }
    func items(for query: SearchQuery) async throws -> [ResultItem]   // 默认返回 []
    func makeCustomView() -> AnyView                                  // 仅 .custom 样式用
    func handleKey(_ press: KeyStroke) -> Bool                        // 默认 false
    func didClose()                                                   // 退出时调用
}
```

### 6.1 三种样式

```swift
public enum ScopeStyle {
    case list                                   // 普通列表
    case listWithPreview(previewRatio: CGFloat = 0.55)   // 左列表右预览
    case custom(height: CGFloat, showsHostInput: Bool)   // 完全自定义
}
```

**`.list`**：最简单，实现 `items(for:)` 即可。作用域内**保持插件给出的顺序**，不会按分数重排，也不应用使用频率加成。

**`.listWithPreview`**：面板变宽，右侧显示当前选中项的 `ResultItem.preview`。剪贴板用它预览图片、富文本和文件。预览视图在选中项变化时重建，保持轻量；重内容（Quick Look、大图）放到异步里加载。

**`.custom`**：由插件提供整个界面。
- `showsHostInput: true`：宿主保留输入框，列表区域换成你的自定义视图。目前没有内置插件使用这种组合，行为以 `LauncherModel` / `LauncherViews` 的源码为准。
- `showsHostInput: false`：宿主**不再提供输入框**，插件自己放文本控件（`ErgoUI.GrowingTextView`）。此时宿主只处理 Esc（隐藏）和 ⌘,（打开设置），其余按键原样交给你的控件。AI 对话就是这种。

### 6.2 键盘

`handleKey` 在宿主处理按键**之前**被调用，返回 `true` 表示你已处理、事件被吞掉。用来实现作用域内的专有快捷键，比如常用语里的 ⌘E 编辑。

宿主的默认按键行为（作用域内也适用）：

| 按键 | 行为 |
|---|---|
| ↑ ↓ / PageUp PageDown | 移动选择（循环） |
| ↩ | 执行选中项的第一个动作 |
| 带修饰键的 ↩ 等 | 执行选中项里 `shortcut` 匹配的动作 |
| ⌘1…⌘9 | 直接执行第 n 项的第一个动作 |
| ⌘K | 打开动作面板（列出该项所有动作） |
| ⌘, | 打开设置 |
| Esc | 有输入则清空；否则隐藏 |
| 退格（输入为空时） | 退出作用域 |

> **输入法**：当输入框处于输入法组字状态（`hasMarkedText`）时，宿主放行**所有**按键，包括回车和方向键，所以你不需要也不应该自己处理组字。

---

## 7. 结果与动作：`ResultItem` / `ResultAction`

```swift
public struct ResultItem {
    public var id: String                  // 在同一插件内唯一，且应当稳定
    public var title: String
    public var subtitle: String?
    public var icon: ResultIcon
    public var accessoryText: String?      // 行右侧的小字，如“⌘1”之外的补充信息
    public var score: Double               // 0...1，默认 0.5
    public var actions: [ResultAction]     // 至少一个；第一个是默认动作
    public var preview: (() -> AnyView)?   // 仅 listWithPreview 使用
}
```

### 7.1 `id` 要稳定

宿主用 `"<pluginID>|<item.id>"` 作为键记录使用频率：用户对某个结果执行动作后，下次相同查询里它的排名会上升（最多加成 0.2）。所以 `id` 应该由**内容**决定（应用的 bundle ID、文件路径、记录主键），不要用每次都变的东西（序号、随机数、时间戳）。同一次搜索里，同一插件内的 `id` 不能重复。

### 7.2 图标

```swift
public enum ResultIcon {
    case symbol(String)                // SF Symbol 名
    case fileIcon(URL)                 // 文件的系统图标
    case appIcon(URL)                  // .app 的图标
    case image(NSImage)
    case bundleAppIcon(bundleID: String)
}
```

文件和应用图标由宿主缓存并异步取，直接给 URL 即可，不要自己在 `search` 里同步取大量图标。

### 7.3 动作

```swift
public struct ResultAction {
    public var id: String
    public var title: String                 // 动作面板（⌘K）里显示
    public var shortcut: KeyStroke?          // nil 表示只能通过回车（第一个动作）或动作面板触发
    public var perform: () async -> ActionOutcome
}

public enum ActionOutcome {
    case hideLauncher            // 关闭启动器（最常用）
    case keepOpen                // 保持打开
    case setQuery(String)        // 把输入框换成这段文字
    case refresh                 // 重新搜索
    case openScope(PluginID)     // 进入某个插件的作用域
}
```

约定的修饰键组合，保持各插件一致：

| 按键 | 含义 |
|---|---|
| ↩ | 主动作（复制、打开、执行） |
| ⌘↩ | 粘贴到前台应用 / 在访达中显示 |
| ⌥↩ | 用结果替换输入框（连续操作） |
| ⇧↩ | 以纯文本粘贴 |

`perform` 是 `async` 的，里面可以 `await` 粘贴、网络请求等。执行期间不要阻塞主线程。

### 7.4 复制与粘贴

```swift
context.pasteboard.copy(.text("..."), marker: nil)
let result = await context.pasteboard.paste(.text("..."), marker: nil, restoreClipboard: true)
```

`PasteContent` 支持文本、富文本、图片（PNG）、文件、链接、颜色。`paste` 的流程：

1. 把内容写入剪贴板；
2. 如果没有“辅助功能”权限，返回 `.copiedOnly(reason:)` 并提示“已复制，按 ⌘V 粘贴”；
3. 否则向**之前的前台应用**模拟 ⌘V；
4. `restoreClipboard: true` 时，约 400ms 后把原来的剪贴板内容写回。

`marker` 用来标记“这次写入是我自己做的”。剪贴板历史插件看到带标记的写入时会忽略，避免把你刚粘贴的内容又记录一遍。需要时传一个能识别的字符串，否则传 `nil`。

粘贴到前台应用的前提是**启动器没有抢走前台**：Ergo 的面板是非激活面板，默认不会调用 `NSApp.activate`。你的作用域或自定义视图不要主动激活应用。

---

## 8. 内联面板：`InlinePanel`

内联面板是出现在结果列表**上方**（或代替列表）的一块自定义区域，用于“不是一行一行的结果”的场景。汇率插件用它显示一排币种卡片。

```swift
public struct InlinePanel {
    public var id: String
    public var height: CGFloat
    public var exclusive: Bool        // true：面板独占，不显示其他结果；false：与结果列表并存
    public var view: AnyView
    public var handleKey: (KeyStroke) -> Bool   // 面板显示时优先收到按键
}
```

在 `SearchProvider.search` 里返回 `.panel(InlinePanel(...))`。面板显示时 `handleKey` 先于宿主处理：汇率插件借此接管 ←/→ 切换卡片。**这意味着面板显示时，输入框里不能用方向键移动光标**，请只拦截你真正需要的键，其余返回 `false`。

---

## 9. 快捷键

在 manifest 里声明动作，在 `perform(hotkey:)` 里响应：

```swift
hotkeys: [
    HotkeyActionDescriptor(
        id: "timestamp.open",
        title: "唤起时间戳",
        defaultTrigger: .doubleTap(.control)
    ),
]

public func perform(hotkey: HotkeyActionID) async {
    guard let context else { return }
    if context.launcher.isVisible { context.launcher.hide() }
    else { context.launcher.show(scope: Self.manifest.id, query: nil) }
}
```

默认触发方式 `HotkeyTrigger`：

| 值 | 含义 |
|---|---|
| `.none` | 默认不绑定，用户可在设置里自行录制 |
| `.combo(KeyCombo(keyCode:modifiers:))` | 组合键。`keyCode` 是 Carbon 虚拟键码（`kVK_*`） |
| `.doubleTap(.control)` | 双击修饰键（Control / Option / Command / Shift） |

用户可以在 设置 → 该插件 里改成别的组合键或别的修饰键，或者关闭；你不需要实现录制界面。宿主负责注册与反注册，插件被停用时它的快捷键自动失效。

注意：

- **双击修饰键需要“输入监控”权限**。把它声明为 `isRequired: false` 的权限，这样用户在没授权时看到的是提示，而不是插件报错。没有权限时设置页会建议改用组合键。
- 组合键不要和系统、其他应用的全局快捷键冲突。`⌘Space` 和 `⌥Space` 是否可用取决于用户机器上的设置。
- 设置页不会替你检查不同插件之间的触发方式是否冲突，请自行避免。

---

## 10. 宿主服务：`PluginContext`

`activate(context:)` 收到的 `context` 是插件与宿主的唯一通道，每个插件拿到的是**属于自己的**一份。

| 成员 | 说明 |
|---|---|
| `pluginID` | 插件 ID |
| `dataDirectory` | 持久数据目录：`~/Library/Application Support/Ergo/Plugins/<id>/`，已创建。放数据库、附件 |
| `cacheDirectory` | 缓存目录：`~/Library/Caches/com.jrainlau.ergo/<id>/`，系统可以清理 |
| `logger` | `os.Logger`，subsystem 为 `com.jrainlau.ergo`，category 为插件 ID |
| `settings` | 设置存储，见下 |
| `secrets` | 钥匙串封装，存 API Key 等 |
| `launcher` | 控制启动器：显示、隐藏、改输入、刷新、打开设置 |
| `pasteboard` | 复制与粘贴 |
| `permissions` | 查询与请求权限 |
| `hud` | 屏幕中央的短暂提示 |
| `usage` | 使用频率记录与加成（一般不用直接调用） |
| `icons` | 取文件和应用图标 |
| `frontApp` | 唤起前的前台应用 |

### 10.1 设置存储

`context.settings` 是一个以 `ergo.plugin.<id>.settings.` 为前缀的 `UserDefaults` 封装，值以 JSON 编码。直接用 `SettingsBox` 最方便：

```swift
public nonisolated struct MySettings: Codable, Equatable, Sendable {
    public var enabledFeature = true
    public init() {}
}

let box = SettingsBox(store: context.settings, key: "main", default: MySettings())
box.value.enabledFeature = false     // 立即落盘
```

`SettingsBox` 是 `@Observable`，可以直接在 SwiftUI 里用 `@Bindable` 绑定，改动立即保存、立即生效。**设置 struct 请加 `nonisolated`**（参考计算器），否则在默认 MainActor 隔离下 `Codable` 的合成会遇到隔离问题。

**给设置加新字段要小心**：`SettingsStore` 解码失败时会整体回落到默认值。Swift 合成的 `Codable` 在 JSON 里缺少某个键时会解码失败，哪怕该属性有默认值。所以给已发布的设置 struct 新增字段时，请自己实现 `init(from:)`，对新字段用 `decodeIfPresent(...) ?? 默认值`，否则用户的旧设置会被重置。

### 10.2 机密

```swift
try context.secrets.setSecret("sk-...", account: "my.plugin.apikey")
let key = context.secrets.secret("my.plugin.apikey")
try context.secrets.setSecret(nil, account: "my.plugin.apikey")   // 删除
```

所有插件共用同一个钥匙串 service（`com.jrainlau.ergo`），`account` 是共享命名空间，**请自己加上插件 ID 前缀**避免冲突。API Key 一律放这里，不要写进设置或数据文件。

### 10.3 启动器控制

```swift
context.launcher.isVisible
context.launcher.show(scope: "ergo.snippets", query: "地址")   // scope 传 nil 则回到主界面
context.launcher.hide()
context.launcher.setQuery("...")
context.launcher.refresh()                                      // 数据变了，重新跑当前查询
context.launcher.openSettings(for: id, openManagement: true)    // 打开设置并定位到你的插件
```

后台数据变化后（例如剪贴板有了新记录）调用 `refresh()` 让当前列表更新；先判断 `isVisible`，隐藏时不需要刷新。

### 10.4 HUD

`context.hud.show("已复制", symbol: "checkmark.circle")`。动作完成后给一个轻量反馈，不要用弹窗。

---

## 11. 设置与管理界面

### 11.1 设置界面

`makeSettingsView()` 返回的视图会被放进该插件设置页的 `Form` 里，所以**返回一个或多个 `Section`** 即可，不要自己包 `Form`：

```swift
public func makeSettingsView() -> AnyView? {
    guard let settings else { return nil }
    return AnyView(MySettingsView(settings: settings))
}

struct MySettingsView: View {
    @Bindable var settings: SettingsBox<MySettings>
    var body: some View {
        Section("外观") {
            Toggle("显示图标", isOn: $settings.value.showIcons)
        }
    }
}
```

插件的启用开关、关键词编辑、快捷键录制、权限状态由宿主统一提供，不用你写。

### 11.2 管理界面

数据量大、需要增删改的插件（常用语、AI 提供商），实现 `makeManagementView()`。设置页里会出现“打开管理…”按钮，界面以弹窗形式呈现（建议最小 800×560）。你也可以在任何时候用 `context.launcher.openSettings(for:openManagement: true)` 直接打开它，常用语的 ⌘E 就是这样做的。

---

## 12. 权限

在 manifest 里声明插件会用到的权限：

```swift
permissions: [
    PermissionRequirement(permission: .accessibility, reason: "把结果直接粘贴到前台应用", isRequired: false),
]
```

| `Permission` | 用途 | 缺失时的行为 |
|---|---|---|
| `.accessibility` | 向前台应用模拟 ⌘V | 退化为只复制，并提示手动粘贴 |
| `.inputMonitoring` | 双击修饰键唤起 | 该快捷键不工作，建议改用组合键 |
| `.fullDiskAccess` | 搜索受保护目录 | 部分目录搜不到 |
| `.pasteboard` | 读取剪贴板 | 无法记录历史 |
| `.screenRecording` | 截图、录屏 | 对应功能不可用 |

声明后：设置 → 权限 页会显示它们的状态和“使用方”；设置 → 该插件页会显示需要的权限。**宿主不会在没有权限时阻止插件运行**，缺权限时的降级由你决定。

运行时检查：

```swift
if context.permissions.status(.accessibility) != .granted {
    // 走降级路径
}
context.permissions.request(.accessibility)               // 触发系统授权弹窗
context.permissions.openSystemSettings(for: .accessibility)
```

原则：能降级就降级，不要因为可选权限没给就抛错；`isRequired: true` 只用于功能确实没法工作的情况。授予“输入监控”后通常需要重启 Ergo 才生效，设置页有“重启 Ergo”按钮。

---

## 13. 可复用工具

`ErgoPluginSupport`（纯逻辑，不依赖 UI，都能在测试里直接用）：

| 工具 | 用途 |
|---|---|
| `FuzzyMatcher.score(query:candidate:pinyinFull:pinyinInitials:)` | 模糊匹配打分，返回 `nil` 表示不匹配。支持子串、首字母、拼音 |
| `Pinyin.convert(_:)` | 中文转拼音全拼与首字母，`hasCJK` 标记是否含中文 |
| `MathExpression.evaluate(_:degrees:)` | 数学表达式求值（加减乘除、幂、阶乘、百分号、常量、函数、十六进制与二进制） |
| `SSEParser` | 逐行喂入，得到 Server-Sent Events；AI 流式输出用它 |
| `DirectoryWatcher` | 基于 FSEvents 的目录监听，带去抖 |
| `FormatHelpers` | 相对时间、字节数、`~` 缩写路径 |
| `ImageTools` | 取图片尺寸、转 PNG、缩略图、降采样加载 |

`ErgoUI`：

| 组件 | 用途 |
|---|---|
| `ResultRowView` / `ResultIconView` | 与主列表一致的结果行与图标，自定义视图里复用以保持外观一致 |
| `Theme` | 圆角、行高、选中色等常量 |
| `GrowingTextView` | 自动增高的多行输入框，带输入法支持，AI 对话用 |
| `QuickLookPreview` | 嵌入式 Quick Look 预览（文件、图片、文本） |
| `IconCache` | 按路径或 bundle ID 取图标并缓存 |
| `WindowDragHandle` | 让一块区域可以拖动窗口 |

写应用名称、文件名搜索时优先用 `FuzzyMatcher` + `Pinyin`，这样自动支持中文拼音；不要自己再写一遍。

---

## 14. 并发与线程约定

整个包启用 Swift 6 严格并发，并设置了 `defaultIsolation(MainActor)`：**不写任何标注的类型和函数默认在 MainActor 上**。这降低了出错概率，但要注意：

- 耗时计算（解析、大量排序、文件扫描）要**离开主线程**。把它写成 `nonisolated static func`，只接收和返回 `Sendable` 的值（`String`、`Data`、`URL`、自定义 `Sendable` struct），再从主线程 `await` 调用：

  ```swift
  nonisolated static func parse(_ text: String) -> [Entry] { ... }

  func search(_ q: SearchQuery) async throws -> SearchOutput {
      let text = q.text
      let entries = await Task.detached(priority: .userInitiated) { Self.parse(text) }.value
      ...
  }
  ```

- 数据库操作（GRDB）放到后台，剪贴板与常用语插件的 store 是参考写法。
- 用 `Timer`、`NSMetadataQuery` 等需要 RunLoop 的东西时，在主线程创建，Timer 加入 `.common` 模式。
- 不要在 `canHandle` 里 `await` 或做 IO。
- C 回调（如 `CGEventTap`）里用 `MainActor.assumeIsolated` 回到主线程。
- `Task` 里捕获 `self` 用 `[weak self]`，插件被停用后实例会被丢弃，不要让后台任务把它拖住。

Settings 的 struct 加 `nonisolated`；纯函数加 `nonisolated`，这样测试里也能直接调用。

---

## 15. 测试

测试 target 通过 `tests(_:_:)` 声明，使用 Swift Testing。能被测的是**纯逻辑**：解析、分类、转换、数据库 store。把它们写成 `nonisolated static func` 或独立的 struct，不要放在需要 `PluginContext` 的类里。

```swift
import Testing
@testable import PluginTimestamp

@Suite struct TimestampTests {
    @Test(arguments: ["1700000000", "1700000000000", "0"])
    func parses(_ s: String) {
        #expect(Double(s) != nil)
    }
}
```

运行：

```sh
make test                                          # 全部
swift test --package-path Packages/ErgoKit --filter PluginTimestampTests
```

涉及系统资源时让测试**隔离**：

- 剪贴板：`NSPasteboard(name: .init("ergo.test.\(UUID())"))`，不要碰 `.general`；
- 钥匙串：`SecretStore(service: "com.jrainlau.ergo.test.\(UUID())")`；
- 设置：`SettingsStore(defaults: UserDefaults(suiteName: ...)!)`；
- 数据库、文件：用 `FileManager.default.temporaryDirectory` 下的唯一目录。

UI 和宿主集成没有自动化测试，靠手动验证：构建后唤起启动器逐条试。

---

## 16. 调试

### 16.1 日志

```swift
context.logger.info("loaded \(count) items")
context.logger.error("failed: \(error.localizedDescription)")
```

不要用 `print`。查看：

```sh
log stream --predicate 'subsystem == "com.jrainlau.ergo"' --info --debug
```

或在“控制台”里按子系统 `com.jrainlau.ergo` 过滤，category 就是你的插件 ID。

### 16.2 Debug 构建的自动化钩子

Debug 构建里，`ErgoApplication.swift` 的 `installDebugHook()` 监听分布式通知 `com.jrainlau.ergo.debug`，可以用脚本驱动启动器，方便做截图和回归：

| `action` | 参数 | 作用 |
|---|---|---|
| `show` | `scope`（插件 ID，可选）、`query` | 唤起启动器，可直接进入某个作用域 |
| `hide` | | 隐藏 |
| `query` | `query` | 设置输入框内容 |
| `key` | `key`（`enter`/`up`/`down`/`left`/`right`/`esc` 或单个字符）、`mods`（`cmd`） | 向启动器发送按键 |
| `settings` | `scope`（插件 ID）、`mods`（`cmd` 表示打开管理界面） | 打开设置并定位到插件 |

这些代码只在 `#if DEBUG` 下编译，Release 构建不包含。

### 16.3 性能

唤起启动器的耗时用 `os_signpost` 记录，类别在 `LauncherWindowController.show` 里。验收标准是唤起 < 50ms、空闲内存 < 80MB。你的插件不应在 `activate` 里做耗时的同步工作；要预热就放到后台。

---

## 17. 常见问题

**插件没出现在设置里。** 检查 `PluginCatalog.all` 是否加了；`Package.swift` 里 `ErgoAppCore` 的依赖是否加了；`make build` 前需要 `xcodegen generate`（`make build` 已包含）。

**关键词输入后没反应。** 关键词只有在插件实现了 `makeScope()` 并返回非 nil 时才生效；确认插件处于 active 状态；检查是否与其他插件冲突（设置页会提示）；`requiresSpace` 为 `true` 时必须输入关键词加一个空格。

**结果排序不对。** 先看 `tier`，它优先于分数；作用域内不重排，顺序就是你返回的顺序；使用频率加成最多 0.2，只在全局搜索里生效。

**`⌘↩` 只复制、没有粘贴。** 没有“辅助功能”权限，这是预期的降级行为。授权后需要对**当前这个签名**的 Ergo 授权，每次换签名都要重新授权，所以开发时请用固定的 Apple Development 证书，不要用 ad-hoc 签名。

**粘贴到了 Ergo 自己。** 你的代码激活了应用（`NSApp.activate`）或让面板成了 key 窗口以外的前台。Ergo 面板是非激活面板，请保持这一点。

**输入法的候选窗不出现 / 回车被吞。** 不要自己拦截输入框的按键，用 `ScopeStyle.custom(showsHostInput: false)` 时用 `GrowingTextView`，它已经处理好组字。

**启用后卡住。** `activate` 里做了同步的重活。把它放到后台 Task，先让 `activate` 返回。

**Swift 并发编译错误。** 多半是跨隔离域传了非 `Sendable` 的值。把计算部分写成 `nonisolated static func`，参数和返回值只用 `Sendable` 类型（见第 14 节）。

---

## 18. API 速查

```swift
// 插件
protocol ErgoPlugin: AnyObject {
    static var manifest: PluginManifest { get }
    init()
    func activate(context: any PluginContext) async throws
    func deactivate() async                                  // 默认空实现
    var searchProvider: (any SearchProvider)? { get }        // 默认 nil
    func makeScope() -> (any PluginScope)?                   // 默认 nil
    func perform(hotkey: HotkeyActionID) async               // 默认空实现
    func makeSettingsView() -> AnyView?                      // 默认 nil
    func makeManagementView() -> AnyView?                    // 默认 nil
}

// 搜索
protocol SearchProvider {
    var participation: SearchParticipation { get }           // .global / .fallback / .none
    var tier: ResultTier { get }                             // .instant < .primary < .secondary < .fallback
    func canHandle(_ query: SearchQuery) -> Bool
    func search(_ query: SearchQuery) async throws -> SearchOutput   // .items / .panel / .none
}

// 作用域
protocol PluginScope {
    var title: String { get }
    var placeholder: String { get }
    var style: ScopeStyle { get }                            // .list / .listWithPreview / .custom
    func items(for query: SearchQuery) async throws -> [ResultItem]
    func makeCustomView() -> AnyView
    func handleKey(_ press: KeyStroke) -> Bool
    func didClose()
}

// 结果
ResultItem(id:title:subtitle:icon:accessoryText:score:actions:preview:)
ResultAction(id:title:shortcut:perform:)         // perform: () async -> ActionOutcome
ActionOutcome: .hideLauncher / .keepOpen / .setQuery(_) / .refresh / .openScope(_)
ResultIcon: .symbol / .fileIcon / .appIcon / .image / .bundleAppIcon

// 快捷键
HotkeyActionDescriptor(id:title:defaultTrigger:)
HotkeyTrigger: .none / .combo(KeyCombo) / .doubleTap(ModifierKey)
KeyStroke(key: LauncherKey, modifiers: ModifierSet)

// 权限
Permission: .accessibility / .inputMonitoring / .fullDiskAccess / .pasteboard / .screenRecording
PermissionRequirement(permission:reason:isRequired:)
```

---

## 参考实现

| 想学什么 | 看哪个插件 |
|---|---|
| 最小的全局搜索 | `PluginCalculator` |
| 索引、文件监听、拼音匹配、使用频率排序 | `PluginAppLauncher` |
| 兜底搜索、异步查询、Quick Look 预览 | `PluginFileSearch` |
| 内联面板、网络请求与缓存 | `PluginCurrency` |
| 数据库、后台监听、`listWithPreview`、双击修饰键快捷键 | `PluginClipboard` |
| 管理界面、占位符展开、导入导出、从作用域跳到管理界面 | `PluginSnippets` |
| 自定义界面、流式网络请求、钥匙串、多提供商配置 | `PluginAIChat` |
