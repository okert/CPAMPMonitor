# CPAMP Monitor for Windows (Preview)

[English](README.md) | [简体中文](README_CN.md)

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

Compatible service: [CPA-Manager-Plus](https://github.com/seakee/CPA-Manager-Plus).
