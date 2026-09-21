# CPAMP Monitor

CPAMP Monitor is a native macOS menu-bar application for viewing provider quota and usage information exposed by a CPAMP-compatible management service.

CPAMP Monitor 是一个原生 macOS 菜单栏应用，用于查看 CPAMP 兼容管理服务提供的账号额度和使用情况。

## 中文

### 功能

- 在菜单栏显示最低剩余额度，点击后查看账号详情。
- 支持 Codex、Antigravity、xAI，并保留 Claude OAuth 额度解析支持。
- 查看 5 小时、周额度、计费周期等窗口及重置时间。
- 查看 CPAMP 提供的请求数、Token、成功率和计算成本历史。
- 支持账号筛选、显示顺序、刷新间隔和告警阈值配置。
- 使用 macOS 通知，并对重复告警进行持久化去重。
- 使用 macOS Keychain 保存管理密钥，不把密钥写入配置文件或命令行参数。
- 支持 HTTPS 直连，也支持通过本机已有 SSH 配置建立可选隧道。

### 系统要求

- macOS 13 或更高版本。
- Apple Silicon 版本可直接使用 GitHub Releases 中的预编译包。
- 使用源码编译需要 Xcode 15+ 或包含 Swift 5.9+ 的 Command Line Tools。
- 需要一个可访问的 CPAMP 管理服务和对应的管理密钥。

### 安装

1. 打开 GitHub Releases，下载最新的 `CPAMP-Monitor-*-macOS-arm64.zip`。
2. 解压后将 `CPAMP Monitor.app` 移到“应用程序”目录。
3. 首次打开时，如果 macOS 阻止未 notarize 的应用，请在“系统设置 -> 隐私与安全性”中允许打开。
4. 在设置窗口填写 CPAMP 管理服务的 HTTPS 地址和管理密钥。

Release 包使用 ad-hoc 签名，不是 Apple Developer ID 签名，也没有经过 notarization。公开分发时请在可信来源下载，并在需要时自行验证 Release 中的 SHA-256 校验文件。

### 从源码编译

```sh
swift run MonitorChecks
zsh scripts/build-app.sh
```

默认输出到 `dist/CPAMP Monitor.app`。`dist/`、`release/` 和 `.build/` 都已加入 Git 忽略规则，不会被提交到仓库。

手动指定输出目录：

```sh
zsh scripts/build-app.sh ./release
```

### 配置与安全

- 设置中填写 CPAMP 管理服务的基础地址，例如 `https://cpamp.example.com`；不要填写模型 API 地址或带密钥的 URL。
- 客户端会拒绝远程 HTTP、URL 中的用户名密码、查询参数和重定向，以避免管理密钥被意外发送。
- 管理密钥保存在当前 macOS 用户的 Keychain 中，Keychain 服务标识为 `local.cpamp.monitor`。
- SSH 模式只使用已有的 SSH 配置和非交互式密钥认证，不会自动接受新主机密钥，也不会修改 SSH 配置。
- 管理密钥权限由 CPAMP 服务决定；本客户端只调用额度、账号历史和提供商查询接口，不能替代服务端权限控制。
- 提供商内部额度接口可能变化；无法识别或已过期的数据会显示为不可用，不会伪造为 0%。

不要把真实地址、管理密钥、账号文件、Keychain 导出内容或个人部署信息提交到公开仓库。

### GitHub Actions 发布

仓库中的 `.github/workflows/release.yml` 会在推送 `v*` 标签后运行检查、构建应用，并在临时的 `release/` 目录中生成 ZIP 包和 SHA-256 文件。构建产物不会提交到 Git 仓库，而会作为 GitHub Release 附件和 Actions artifact 保存。

```sh
git tag v0.1.0
git push origin v0.1.0
```

工作流使用 GitHub 托管的 macOS runner 构建 Apple Silicon 版本，并自动生成 Release notes。版本号来自 Git 标签；例如 `v0.2.0` 会生成 `0.2.0` 应用版本。

### 测试

`MonitorChecks` 是不依赖 XCTest 的轻量测试运行器，适用于只安装了 Command Line Tools 的 macOS。它覆盖 URL 安全校验、额度解析、空值处理、过期数据、告警去重、周期切换和账号身份等核心逻辑。

```sh
swift run MonitorChecks
```

## English

### Features

- Shows the lowest fresh remaining percentage in the menu bar and account details in a popover.
- Supports Codex, Antigravity and xAI, with Claude OAuth quota parsing support.
- Displays quota windows, reset times and CPAMP usage history.
- Configures account selection and order, refresh interval and warning thresholds.
- Sends macOS notifications with persistent per-account and per-cycle deduplication.
- Stores the management key in macOS Keychain instead of source files or command-line arguments.
- Supports direct HTTPS and an optional tunnel built from the user's existing SSH configuration.

### Requirements

- macOS 13 or later.
- The prebuilt GitHub Release is currently for Apple Silicon Macs.
- Source builds require Xcode 15+ or Command Line Tools that provide Swift 5.9+.
- A reachable CPAMP-compatible management service and management key.

### Installation

1. Open GitHub Releases and download the latest `CPAMP-Monitor-*-macOS-arm64.zip`.
2. Extract it and move `CPAMP Monitor.app` to Applications.
3. If macOS blocks the non-notarized app on first launch, allow it in System Settings under Privacy & Security.
4. Enter the CPAMP management service HTTPS address and management key in Settings.

Release packages use an ad-hoc signature. They are not signed with an Apple Developer ID certificate and are not notarized. Download from a trusted source and use the SHA-256 file from the Release when verification is needed.

### Build From Source

```sh
swift run MonitorChecks
zsh scripts/build-app.sh
```

The default output is `dist/CPAMP Monitor.app`. `dist/`, `release/` and `.build/` are ignored by Git and are not part of the source repository.

To choose another output directory:

```sh
zsh scripts/build-app.sh ./release
```

### Configuration and Security

- Enter the CPAMP management service base URL, for example `https://cpamp.example.com`. Do not enter a model API URL or a URL containing a key.
- The client rejects remote HTTP, embedded credentials, query parameters and redirects to reduce accidental credential disclosure.
- The management key is stored in the current macOS user's Keychain under the `local.cpamp.monitor` service.
- SSH mode uses existing SSH configuration and non-interactive key authentication. It does not accept new host keys or modify SSH configuration.
- The CPAMP service remains responsible for authorization. This client only requests account history, quota and provider data; it is not a server-side read-only boundary.
- Provider quota endpoints are internal and may change. Unknown or expired data is shown as unavailable rather than fabricated as zero.

Do not commit real service addresses, management keys, account files, Keychain exports or personal deployment details to a public repository.

### GitHub Actions Releases

`.github/workflows/release.yml` runs checks and builds the app after a `v*` tag is pushed. It creates a temporary `release/` directory containing the ZIP package and SHA-256 file. Build outputs are not committed; they are uploaded as GitHub Release assets and an Actions artifact.

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow uses a GitHub-hosted macOS runner to build the Apple Silicon package and generates Release notes automatically. The app version comes from the tag, so `v0.2.0` produces version `0.2.0`.

### Tests

`MonitorChecks` is a lightweight test runner that does not depend on XCTest, so it also works with Command Line Tools only. It covers URL security validation, quota parsing, null handling, stale data, alert deduplication, reset cycles and credential identity.

```sh
swift run MonitorChecks
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
