# Ergo

一个由插件驱动的 macOS 效率启动器。按下全局快捷键唤起一个输入框，搜索应用、算数、查汇率、翻剪贴板历史、插入常用语、和 AI 对话，都在同一个入口里完成。

- 原生 AppKit + SwiftUI，Swift 6
- 所有功能都是插件，内置插件和自己写的用同一套接口
- 界面以中文为主，支持中文拼音全拼与首字母搜索
- 要求 macOS 26 及以上

## 安装

### 下载 DMG（推荐）

到 [Releases](https://github.com/jrainlau/ergo/releases) 下载最新的 `Ergo-x.y.z.dmg`，打开后**双击「安装 Ergo.command」**：脚本会把 **Ergo** 装进「应用程序」、解除 Gatekeeper 隔离并启动。也可以先手动把 Ergo 拖进「应用程序」，再双击该脚本。

发布的构建使用 ad-hoc 签名（没有 Apple 开发者证书），首次打开会被 Gatekeeper 拦截；脚本做的就是下面这条命令，不想用脚本也可以自己在终端执行一次：

```sh
xattr -dr com.apple.quarantine /Applications/Ergo.app
```

然后再启动。因为 ad-hoc 签名每次构建都不同，**升级到新版本后系统可能要求重新授权**辅助功能和输入监控：到 系统设置 › 隐私与安全性 里先移除旧的 Ergo 条目，再重新添加。

### 自己编译

要求：macOS 26+、Xcode 27、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig   # 填入自己的 DEVELOPMENT_TEAM
make build                # 生成工程并构建到 build/
./scripts/run.sh          # 启动（找不到构建产物时会先构建）；make run 效果相同
make test                 # 运行 ErgoKit 的全部测试
```

建议使用 **Apple Development 证书**（免费的个人 Team 即可）自签。用 ad-hoc 签名自己编译的话，每次构建签名都会变，辅助功能和输入监控权限会反复失效。

## 使用

默认唤起快捷键是 `⌥Space`，可以在 设置 › 通用 里改成别的组合，例如 `⌘Space`（需要先在系统设置里关闭“聚焦搜索”的同名快捷键）。

| 按键 | 作用 |
|---|---|
| `↑` `↓` | 移动选择 |
| `↩` | 执行默认动作 |
| `⌘↩` | 粘贴到前台应用（计算器、剪贴板、常用语等）；文件搜索里是“在访达中显示” |
| `⌘1`…`⌘9` | 直接执行第 n 项 |
| `⌘K` | 打开当前结果的动作面板 |
| `⌘,` | 打开设置 |
| `Esc` | 清空输入；输入为空时隐藏 |
| 退格（输入为空） | 退出当前插件的作用域 |

输入中文拼音时，回车和方向键用于输入法选词，启动器不会拦截。

## 内置插件

| 插件 | 触发方式 | 说明 |
|---|---|---|
| 应用启动 | 直接输入 | 支持中文、拼音全拼与首字母，用得越多排得越前 |
| 文件搜索 | `f ` / `'`，或没有其他结果时兜底显示最多 5 条 | 基于 Spotlight，带 Quick Look 预览 |
| 计算器 | 直接输入算式，如 `1+1`、`sqrt(16)`、`2pi` | 同时给出十进制 / 十六进制 / 二进制 |
| 汇率 | `$100`、`100 usd to jpy`、`100 美元` | Frankfurter / ExchangeRate-API，每日更新，离线时使用缓存 |
| 剪贴板 | 双击 `Control`，或 `cb` | 文本、富文本、图片、文件、链接、颜色；带预览、置顶、保留时长；不记录被密码管理器标记为敏感的内容 |
| 常用语 | `sn` | 支持 `{date}` `{time}` `{datetime}` `{clipboard}` `{uuid}` `{cursor}` 占位符，可导入导出 JSON |
| AI 问答 | `ai` | OpenAI 兼容接口与 Anthropic，流式输出、Markdown、历史会话；API Key 保存在钥匙串 |
| 翻译 | 直接输入文字，或 `translate ` 加空格再输入 | 自动判断语言，默认中英互译；没有应用等强匹配时译文排第一行，有匹配时排在它们后面；回车复制译文 |

每个插件都可以在 设置 › 插件 里单独启用或停用、修改关键词和快捷键。

### AI 问答的配置

设置 › AI 问答 › 添加提供商，选择预设（或自定义 Base URL），填入 API Key，可以点“获取模型列表”拉取模型、“测试连接”验证。输入 `ai` 进入对话：`↩` 发送，`Esc` 停止生成，`⌘N` 新建会话。

### 翻译的配置

翻译按优先级依次尝试几个引擎，取第一个成功的结果，全部都可以在 设置 › 翻译 里开关和调整顺序：

| 引擎 | 适用 | 说明 |
|---|---|---|
| 牛津英汉汉英词典 | 中英单词与短语 | 用 macOS 自带的系统词典，离线即时。没安装时在“词典”App 的设置里勾选「简体中文 – 英文」，系统会自动下载 |
| 系统翻译 | 句子与段落，多种语言 | 用 macOS 自带的离线翻译。首次使用需要下载语言包，设置页里有按钮 |
| 大模型 | 任意文字，可附加提示词 | 添加 OpenAI 兼容接口或 Anthropic，填入 API Key（保存在钥匙串）。默认只在 `translate` 关键词里使用；打开“主搜索框自动翻译时也使用大模型”后，主搜索框也会调用 |

- 默认只有中 ↔ 英一个语言对。可以在设置里添加更多（如 英 ↔ 日），输入属于语言对里的某一种，就翻译成另一种。
- 主搜索框里的译文：`↩` 复制，`⌘↩` 粘贴到前台应用，`⌥↩` 用译文替换输入；词典结果还有 `⌘⇧C` 复制完整词条。
- 不想在主搜索框里自动翻译，可以在设置里关掉，仍可用 `translate ` 触发。

## 权限

| 权限 | 用途 | 没有时 |
|---|---|---|
| 辅助功能 | 向前台应用模拟 `⌘V` | 退化为只复制，并提示手动粘贴 |
| 输入监控 | 「双击修饰键」快捷键 | 该快捷键不可用，可改用组合键；授权后需重启 Ergo |
| 完全磁盘访问 | 可选，搜索受保护的目录 | 部分目录搜不到 |
| 剪贴板读取 | 记录剪贴板历史 | 无法记录 |

设置 › 权限 页会实时显示状态并提供“打开系统设置”和“重启 Ergo”按钮。应用没有启用 App Sandbox。

## 开发插件

插件是编译进应用的 SwiftPM target，只依赖 `ErgoPluginKit`、`ErgoPluginSupport`、`ErgoUI` 和第三方库。新增一个插件只需要：新建 target、实现 `ErgoPlugin` 协议、在 `PluginCatalog.swift` 里加一行。

完整教程见 **[docs/PLUGIN_DEVELOPMENT.md](docs/PLUGIN_DEVELOPMENT.md)**：从零写一个插件、搜索与作用域、结果与动作、快捷键、设置与权限、并发约定、测试与调试。

## 项目结构

```
App/                    应用入口、Info.plist、资源（图标、String Catalog）
Config/                 xcconfig（本地签名配置 Signing.local.xcconfig 不入库）
scripts/                run.sh 启动脚本、make-dmg.sh 打包 DMG、dmg/ 放进 DMG 的安装脚本
docs/                   文档
.github/workflows/      发布工作流
Packages/ErgoKit/
  ErgoPluginKit         插件 SDK：只有协议和值类型
  ErgoPluginSupport     可复用工具：模糊匹配、拼音、表达式求值、SSE、目录监听
  ErgoUI                共享 SwiftUI / AppKit 组件
  ErgoCore              宿主服务：插件宿主、设置、钥匙串、粘贴、权限、快捷键
  ErgoLauncher          启动器面板
  ErgoSettings          设置窗口与引导
  ErgoAppCore           组合根：AppDelegate、状态栏、PluginCatalog
  Plugin*               各内置插件，每个一个 SwiftPM target
```

约定：Swift 6 严格并发，默认 MainActor 隔离；日志用 `os.Logger`（subsystem `com.jrainlau.ergo`），不用 `print`；每个模块自带 `Resources/Localizable.xcstrings`，便于后续添加其他语言。

## 发布（GitHub Actions）

`.github/workflows/release.yml` 在每次推送时自动构建并发布 DMG：

| 触发 | 结果 |
|---|---|
| 推送到 `main` | 运行测试，构建 Release，打包 DMG，发布预发布版本，版本号和 tag 都是 `x.y.<序号>`（如 `0.1.37`） |
| 推送 `x.y.z` 标签（如 `git tag 0.2.0 && git push origin 0.2.0`） | 同上，但以标签为版本号，发布为正式版本 |
| 手动运行（workflow_dispatch） | 同推送到 `main` |

DMG 与对应的 `.sha256` 会作为 Release 附件上传，同时保存为 Actions 构建产物。版本号和 tag 一律是 `x.y.z`，**不带 `v` 前缀**，不符合格式的标签会让构建失败。推送到 `main` 时，`x.y` 取自 `project.yml` 里的 `MARKETING_VERSION`，`z` 是工作流的运行序号；要升 `x.y` 就改这个值。构建时版本号会写入应用本身（`CFBundleShortVersionString`），所以应用里显示的版本和 tag 一致。

CI 构建使用 ad-hoc 签名；如果以后有 Developer ID 证书，可以在工作流里加上签名和公证步骤，用户就不再需要手动去除隔离属性了。

## 应用内自动更新

应用每 6 小时（以及启动后约 20 秒）请求一次 GitHub Releases API（`https://api.github.com/repos/jrainlau/ergo/releases`），按版本号挑出最新的 `x.y.z` Release；比当前版本新时，下载其 DMG，用 Release 附件的 sha256 校验，再校验 `.app` 的签名、Bundle ID 和版本号，然后询问是否更新。确认后应用退出，由一个独立的 shell 脚本替换 `.app`（失败则回滚）、去除隔离属性并重新启动。应用内下载不带隔离属性，所以更新不会再触发“仍要打开”。

- 设置 › 关于 › 更新：开关自动检查、是否包含预发布版本（默认包含，因为推送到 `main` 的构建都是预发布）、手动检查。菜单栏菜单里也有「检查更新…」。
- 只有安装在 `/Applications` 或 `~/Applications` 且有写权限时才会自动替换，否则只会打开 DMG 让你手动安装；Debug 构建不会自动检查。
- 版本信息直接来自 Releases API（含 DMG 地址、sha256、更新说明），不需要额外维护 `versions.json`。

## 本地打 DMG

```sh
xcodegen generate
xcodebuild -project Ergo.xcodeproj -scheme Ergo -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
codesign --force --deep --sign - build/Build/Products/Release/Ergo.app
./scripts/make-dmg.sh build/Build/Products/Release/Ergo.app dist/Ergo.dmg
```
