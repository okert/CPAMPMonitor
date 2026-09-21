# CPAMP Monitor

[English](README.md) | [简体中文](README_CN.md)

CPAMP Monitor is a native macOS menu-bar application for viewing provider quota and usage information exposed by a CPAMP-compatible management service.

A native **Windows client (preview)** is also available, built with C# / WPF, without WebView or Electron. It supports x64 and ARM64, direct HTTPS connections, tray monitoring, notifications, Credential Manager storage and sign-in startup. SSH is not included in the Windows version. See [Windows setup and validation status](windows/README.md).

Windows preview downloads are published separately under `windows-v*` in [Releases](https://github.com/okert/CPAMPMonitor/releases). The stable macOS release remains unchanged. Real-machine Windows acceptance testing is pending; automated builds and smoke checks are not a substitute for it.

## Features

- Shows the lowest fresh remaining percentage in the menu bar and account details in a popover.
- Supports Codex, Antigravity and xAI, with Claude OAuth quota parsing support.
- Displays quota windows, reset times and CPAMP usage history.
- Configures account selection and order, refresh interval and warning thresholds.
- Sends macOS notifications with persistent per-account and per-cycle deduplication.
- Stores the management key in macOS Keychain instead of source files or command-line arguments.
- Supports direct HTTPS and an optional tunnel built from the user's existing SSH configuration.

## Screenshots

The screenshots show the menu-bar dashboard and the settings window. Account identifiers are masked and the service address in the settings screenshot is an example address.

<p align="center">
  <img src="docs/images/cpamp-monitor-dashboard.png" alt="CPAMP Monitor dashboard" width="420">
  <img src="docs/images/cpamp-monitor-settings.png" alt="CPAMP Monitor settings" width="420">
</p>

## Compatible Service

CPAMP Monitor is a client for CPAMP-compatible management services. The reference service project is [CPA-Manager-Plus](https://github.com/seakee/CPA-Manager-Plus). This repository contains the macOS monitor client, not the service itself.

## Requirements

- macOS 13 or later.
- GitHub Releases provide packages for Apple Silicon (`arm64`) and Intel (`x86_64`) Macs.
- Source builds require Xcode 15+ or Command Line Tools that provide Swift 5.9+.
- A reachable CPAMP-compatible management service and management key.

## Installation

1. Open [GitHub Releases](https://github.com/okert/CPAMPMonitor/releases) and download the package for your Mac: `macOS-arm64` for Apple Silicon or `macOS-x86_64` for Intel.
2. Extract it and move `CPAMP Monitor.app` to Applications.
3. If macOS blocks the non-notarized app on first launch, allow it in System Settings under Privacy & Security.
4. Enter the CPAMP management service HTTPS address and management key in Settings.

Release packages use an ad-hoc signature. They are not signed with an Apple Developer ID certificate and are not notarized. Download from a trusted source and use the SHA-256 file from the Release when verification is needed.

## Build From Source

```sh
swift run MonitorChecks
zsh scripts/build-app.sh
```

The default output is `dist/CPAMP Monitor.app` for the current machine architecture. `dist/`, `release/` and `.build/` are ignored by Git and are not part of the source repository.

To choose another output directory:

```sh
zsh scripts/build-app.sh ./release
```

To build a specific architecture from a compatible macOS toolchain:

```sh
APP_ARCH=arm64 zsh scripts/build-app.sh ./release/arm64
APP_ARCH=x86_64 zsh scripts/build-app.sh ./release/x86_64
```

## Configuration and Security

- Enter the CPAMP management service base URL, for example `https://cpamp.example.com`. Do not enter a model API URL or a URL containing a key.
- The client rejects remote HTTP, embedded credentials, query parameters and redirects to reduce accidental credential disclosure.
- The management key is stored in the current macOS user's Keychain under the `local.cpamp.monitor` service.
- SSH mode uses existing SSH configuration and non-interactive key authentication. It does not accept new host keys or modify SSH configuration.
- The CPAMP service remains responsible for authorization. This client only requests account history, quota and provider data; it is not a server-side read-only boundary.
- Provider quota endpoints are internal and may change. Unknown or expired data is shown as unavailable rather than fabricated as zero.

Do not commit real service addresses, management keys, account files, Keychain exports or personal deployment details to a public repository.

## GitHub Actions Releases

`.github/workflows/release.yml` runs checks and builds Apple Silicon and Intel apps after a `v*` tag is pushed. It creates a temporary `release/` directory containing both ZIP packages and their SHA-256 files. Build outputs are not committed; they are uploaded as GitHub Release assets and an Actions artifact.

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow uses a GitHub-hosted macOS runner to build both architectures and generates Release notes automatically. The app version comes from the tag, so `v0.2.0` produces version `0.2.0`.

## Tests

`MonitorChecks` is a lightweight test runner that does not depend on XCTest, so it also works with Command Line Tools only. It covers URL security validation, quota parsing, null handling, stale data, alert deduplication, reset cycles and credential identity.

```sh
swift run MonitorChecks
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
