# Changelog

所有项目变动都记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [0.1.1] - 2026-08-25

### Added
- M1-M10 完整实现
- Tunnel Engine 独立 Swift Package(`JanusSSHTunnelEngine`)
- Domain Models:Profile / PortForward / Tunnel / TunnelState / TunnelError
- ProfileValidator:字段校验 + 跨 Profile 端口冲突检测
- AtomicFileStore:tmp + fsync + rename + .bak 保留
- JSONProfileRepository:版本化 envelope + 时间戳备份 + 轮转 10 个
- AppSettings + JSONSettingsRepository
- SSHCommandBuilder:强制 `-N` / `-o ExitOnForwardFailure=yes` / 不走 shell
- SSHProcess (actor):三流合一( stdout / stderr / terminated)
- SSHProcessManager:多 Profile 生命周期管理
- PortChecker:本地端口占用检测
- SSHConfigParser:简化版 ~/.ssh/config 解析
- SSHConfigService:`ssh -G` Host 解析 + Test Connection
- ReconnectController:指数退避 1s/2s/5s/10s/30s
- TunnelLogStore:per-Profile 1000 行环形缓冲
- TunnelManager (@MainActor @Observable):Start/Stop/Restart + Start All/Stop All
- 10 个 ADR(架构决策记录)
- SwiftUI 6 个屏幕(Dashboard / Editor / Running / Hosts / Settings / Menu Bar)
- macOS 集成:MenuBarExtra / SMAppService / UserNotifications
- Info.plist + Entitlements(Sandbox OFF + Hardened Runtime)
- Homebrew Cask 模板
- Docker 集成测试 fixtures
- GitHub Actions CI + Release 工作流


### Fixed
- DMG 安装后启动崩溃 (`dyld: Symbol missing: _$s20JanusSSHTunnelEngine13TunnelManagerC07processE0...`)。
  根因有两层:
  1. 之前打的 DMG 是 **Debug 构建**(含 `JanusSSH.debug.dylib` + `__preview.dylib`),
     主 dylib 的 rpath 硬编码到打包机的 `~/Library/Developer/Xcode/DerivedData/...` 路径,
     用户机上 dyld 找不到 framework → 任何跨模块符号都报 Symbol missing。
  2. 这个工程的 Xcode project 里 **缺一个 "Embed Frameworks" build phase**
     (`.app/Contents/Frameworks/` 永远是空的),
     即使 Release 构建,主 binary 的 rpath `@executable_path/../Frameworks` 也指向不存在的目录。
- `scripts/release.sh` 里 xcodebuild 的 `-project` 路径错指根目录的
  `JanusSSH.xcodeproj`(项目在 commit 8515a6a 之后已经移到 `JanusSSH/` 子目录)。
- `scripts/release.sh` 加了一个 # 1.5 步:把
  `Build/Products/Release/PackageFrameworks/*.framework` 用 `ditto` 拷进
  `JanusSSH.app/Contents/Frameworks/`(用 Developer ID 重签),
  保证打出来的 .app 自包含、可分发。

## [0.1.0] - 2026-08-18

### Initial Prototype
- 原型设计稿(7 个 HTML 页面,OpenDesign 产出)
- JanusSSH 命名收敛:"原生 macOS App + 独立 Tunnel Engine + OpenSSH"三层架构
- 技术栈锁定:Swift 6 + SwiftUI + Observation + actor + Foundation Process + Network + Codable + OSLog + MenuBarExtra + SMAppService

[Unreleased]: https://github.com/lshgdut/janus-ssh/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/lshgdut/janus-ssh/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/lshgdut/janus-ssh/releases/tag/v0.1.0