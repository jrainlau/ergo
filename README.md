# Ergo

个人 macOS 效率启动器：全局快捷键唤起一个输入框，所有功能都以插件形式提供。

## 内置插件

| 插件 | 触发方式 | 说明 |
|---|---|---|
| 应用启动 | 直接输入 | 支持中文、拼音全拼与首字母，使用频率会影响排序 |
| 文件搜索 | `f ` / `'`，或没有其他结果时兜底显示最多 5 条 | 基于 Spotlight（`NSMetadataQuery`），带 QuickLook 预览 |
| 计算器 | 直接输入算式 | 同时给出十进制 / 十六进制 / 二进制 |
| 汇率 | `$100`、`100 usd to jpy`、`100 美元` | Frankfurter / ExchangeRate-API，每日更新，离线时使用缓存 |
| 剪贴板 | 双击 Control，或 `cb` | 文本、富文本、图片、文件、颜色，带预览和置顶 |
| 常用语 | `sn` | 支持 `{date}` `{time}` `{clipboard}` `{uuid}` `{cursor}`，可导入导出 JSON |
| AI 问答 | `ai` | OpenAI 兼容接口与 Anthropic，流式输出、Markdown、历史会话；Key 存钥匙串 |

默认唤起快捷键为 `⌥Space`（`⌘Space` 被聚焦搜索占用），可在设置中修改。`⌘K` 打开当前结果的动作面板，`⌘,` 打开设置。

## 构建

要求：macOS 26+、Xcode 27、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig   # 填入自己的 DEVELOPMENT_TEAM
make build   # 生成工程并构建到 build/
make run     # 构建并启动
make test    # 运行 ErgoKit 的全部测试
```

## 结构

```
App/                    应用入口、Info.plist、资源（图标、String Catalog）
Config/                 xcconfig（本地签名配置不入库）
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

依赖规则：插件只能依赖 `ErgoPluginKit`、`ErgoPluginSupport`、`ErgoUI` 与第三方库，不能依赖宿主模块或其他插件。新增插件只需在 `PluginCatalog.swift` 里加一行。

## 权限

- 辅助功能：向前台应用模拟 `⌘V`（未授权时退化为只复制）
- 输入监控：「双击修饰键」快捷键
- 完全磁盘访问：可选，用于搜索受保护目录

应用未启用 App Sandbox，使用 Apple Development 证书签名。界面以中文为主，字符串目录位于 `App/Resources/Localizable.xcstrings`，便于后续添加其他语言。
