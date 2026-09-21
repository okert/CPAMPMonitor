# CPAMP Monitor for Windows (Preview)

Native C# / WPF desktop client. No WebView, Electron or SSH. Supports x64 and ARM64 Windows PCs. This is a preview pending real-machine acceptance testing.

## Run

1. Download `win-x64` for Intel/AMD PCs, or `win-arm64` for Windows on ARM.
2. Extract the entire ZIP into a permanent, user-writable folder.
3. Run `CPAMPMonitor.exe`. The .NET runtime is bundled; no separate runtime installation is required.
4. Enter the CPAMP management HTTPS URL and management key in Settings. Blank key retains the credential already stored for that exact normalized address.

Windows 11 is recommended. Windows 10 22H2 is also a target but has not been tested on a real machine. Downloads are unsigned and may be flagged by SmartScreen; verify the source and SHA-256 before approving execution. Do not disable system security globally.

Closing the dashboard leaves the monitor running in the notification area. Quit from the tray menu or power button. Windows may place its icon in the tray overflow. Notifications use the native notification-area balloon API and respect system suppression / Do Not Disturb. The API does not confirm that a notification was displayed.

Settings and deduplication history are stored under `%LOCALAPPDATA%\CPAMPMonitor`. Management keys are stored only in Windows Credential Manager under `CPAMPMonitor:<hash-of-normalized-service-url>`. Changing the service address requires a key for the new address. Sign-in startup uses the current user's `Run` registry key and needs no administrator access. Disable sign-in startup before moving or deleting the executable folder. To uninstall, disable startup, quit, remove the extracted folder and optionally remove the settings folder and matching Credential Manager entries.

## Build and Check

Requires .NET 10 SDK. On Windows:

```powershell
dotnet run --project windows/MonitorChecks -c Release
./scripts/build-windows.ps1 -Runtime win-x64
./scripts/build-windows.ps1 -Runtime win-arm64
```

Core checks can also run on macOS/Linux. WPF, Windows Credential Manager and notification-area behavior require Windows. GitHub Actions builds each architecture on its native runner, validates the executable architecture and runs a synthetic WPF/Credential Manager smoke test. The smoke test never connects to a real service. `windows-v*` tags publish a Windows prerelease without changing the stable macOS release.

## Real-Machine Acceptance Checklist

- Launch on a clean Windows x64 machine, then repeat on ARM64 hardware.
- Connect to a test CPAMP service; compare Codex, Antigravity, xAI and Claude quota windows and history against the service.
- Confirm missing/expired quota is unavailable, not 0%; test offline, invalid key, redirect and rate-limit errors.
- Save, restart and confirm Credential Manager retention, account selection/order and warning thresholds.
- Test refresh, pause/resume, close-to-tray, second launch, service dashboard and quit.
- Verify test notifications and warning/critical deduplication across restarts and quota resets.
- Verify sign-in startup, sleep/resume, 100/150/200% display scaling and multiple monitors.
- Confirm no management key appears in settings JSON, process arguments, screenshots or error messages.

## 中文

这是原生 C# / WPF Windows 客户端，不使用网页套壳，不包含 SSH。Intel/AMD 电脑选择 `win-x64`，Windows ARM 电脑选择 `win-arm64`。完整解压后运行 `CPAMPMonitor.exe`，无需另外安装 .NET 运行时。

设置中填写 CPAMP 管理服务 HTTPS 地址和管理密钥；同一地址下密钥留空会保留已保存的密钥。密钥使用 Windows 凭据管理器保存，不写入配置 JSON。关闭面板后程序仍在系统托盘运行；退出需使用托盘菜单或退出按钮。通知显示受 Windows 通知设置和免打扰模式影响。

建议使用 Windows 11。当前为未经签名的预览版，自动编译和基础检查不能替代实机验证。请先在测试环境验证连接、托盘、通知、开机启动、睡眠唤醒和缩放，再用于日常监控。移动或删除程序目录前请先关闭开机启动。

适配服务：[CPA-Manager-Plus](https://github.com/seakee/CPA-Manager-Plus)。
