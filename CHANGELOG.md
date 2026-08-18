# Changelog

所有项目变动都记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [Unreleased]

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

## [0.1.0] - 2026-08-18

### Initial Prototype
- 原型设计稿(7 个 HTML 页面,OpenDesign 产出)
- JanusSSH 命名收敛:"原生 macOS App + 独立 Tunnel Engine + OpenSSH"三层架构
- 技术栈锁定:Swift 6 + SwiftUI + Observation + actor + Foundation Process + Network + Codable + OSLog + MenuBarExtra + SMAppService

[Unreleased]: https://github.com/lshgdut/janus-ssh/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lshgdut/janus-ssh/releases/tag/v0.1.0