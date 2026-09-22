# CPAMP Monitor Windows 版

[English](README.md) | [简体中文](README_CN.md)

原生 C# / WPF Windows 客户端，不使用 WebView、Electron 或其他网页套壳，不包含 SSH。提供 x64 和 ARM64 版本。

## 使用

1. Intel/AMD 电脑下载 `win-x64`，Windows ARM 电脑下载 `win-arm64`。
2. 将整个 ZIP 解压到固定、当前用户可写的目录。
3. 运行 `CPAMPMonitor.exe`。安装包包含 .NET 运行时，无需另外安装。
4. 在设置中填写 CPAMP 管理服务 HTTPS 地址和管理密钥。同一规范化地址下密钥留空会保留已保存的密钥；新地址必须填写对应密钥。托盘显示可以分别选择账号和额度窗口，例如 5 小时或周额度；保持默认选项即可继续显示对应范围内的最低新鲜额度。

建议使用 Windows 11。Windows 10 22H2 也是目标系统，但尚未经实机验证。预览包未签名，可能触发 SmartScreen 提醒；请先核对下载来源及 SHA-256，不要全局关闭系统安全功能。

关闭监控面板后程序仍在系统托盘运行。退出需使用托盘菜单或退出按钮；Windows 可能将图标收入托盘折叠菜单。通知使用原生系统托盘通知接口，显示受系统通知设置和免打扰模式影响，接口不能确认用户实际看到了通知。

配置与告警去重记录保存在 `%LOCALAPPDATA%\CPAMPMonitor`，管理密钥只保存在 Windows 凭据管理器中，对应条目为 `CPAMPMonitor:<规范化服务地址的哈希>`。开机启动使用当前用户的 `Run` 注册表项，不需要管理员权限。

移动或删除程序目录前，请先关闭开机启动。卸载时先关闭开机启动并退出程序，再删除解压目录；如需清除全部数据，还需删除上述配置目录和凭据管理器中对应的条目。

## 编译与检查

需要 .NET 10 SDK，在 Windows 上执行：

```powershell
dotnet run --project windows/MonitorChecks -c Release
./scripts/build-windows.ps1 -Runtime win-x64
./scripts/build-windows.ps1 -Runtime win-arm64
```

核心检查也可以在 macOS/Linux 上运行。WPF、Windows 凭据管理器和托盘行为需要 Windows。GitHub Actions 分别在两种架构的原生 Windows runner 上编译，校验 EXE 架构，并使用虚构数据执行界面和凭据管理器基础检查，不连接真实服务。

稳定的 `v*` 标签会将 macOS 和 Windows 的全部架构包发布到同一个 Release 中。

## 实机验收清单

- 在干净的 Windows x64 系统启动，然后在 ARM64 硬件上重复验证。
- 连接测试 CPAMP 服务，核对 Codex、Antigravity、xAI、Claude 额度窗口及历史用量。
- 确认未知或过期额度显示为不可用，而不是 0%；测试断网、错误密钥、重定向和限流。
- 保存并重启，确认凭据保留、账号筛选与排序、告警阈值恢复正常。
- 验证刷新、暂停/恢复、关闭到托盘、重复启动、打开后台与退出。
- 验证测试通知、提醒/紧急阈值、跨重启及额度周期的告警去重。
- 验证开机启动、睡眠唤醒、多显示器和 100%/150%/200% 缩放。
- 确认配置 JSON、进程参数、截图和错误消息不包含管理密钥。

适配服务：[CPA-Manager-Plus](https://github.com/seakee/CPA-Manager-Plus)。
