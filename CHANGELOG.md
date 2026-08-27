# Changelog

所有项目变动都记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [0.2.0] - 2026-08-26

### Changed
- `scripts/release.sh` 默认签名改成 **ad-hoc** (`CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--}`)。
  本地构建跟 CI 流水线共用一套路径 — 通过 `export CODE_SIGN_IDENTITY=...` / `DEVELOPMENT_TEAM=...` /
  `KEYCHAIN_PROFILE=...` 三个 env 切到 Developer ID + Apple 公证的真签全链路。
- StatusBadge `.running` halo 动画:周期 1.4s → 2.6s + 实色圆 → RadialGradient 软边 +
  scaleEffect 收紧到 1.2×~2.4×。MenuBarProfileRow 加 `.clipShape(RoundedRectangle(cornerRadius: 6))`
  兜底,防止动画细节溢出 hover 框。
- MenuBarProfileRow 状态 Pill 从 Spacer 推到右侧改为紧贴 profile title,贴一行读。

### Added
- `Makefile` — `make help / build / test / release / dmg / dmg-quick / clean` 一组命令,
  让"手动打包"路径(`dmg` / `dmg-quick`)以 Make target 形式存在,不再依赖 shell 记忆。
- `Resources/RELEASE-README.md` — 嵌入 DMG 内的用户安装说明(三步:拖 .app →
  解除 quarantine → 启动;ad-hoc 包需要手动 `xattr -dr`)。
- `Resources/install-unquarantine.command` — 双击在 Terminal 跑,去掉
  `com.apple.quarantine` 标记,等同 Finder 右键 Open 一次。幂等 — 在 Developer ID
  构建产物上 no-op。
- `scripts/release.sh` 把上述两份文件嵌进 DMG staging(`$BUILD_DIR/dmg/`)。
- `Tunnel.markStopping()` + `Tunnel.markStopped(now:)` 两个 `mutating` 方法,集中
  stop 状态机的契约,让 `stop(profileID:)` 和 `stopAll()` 共享同一个收尾约定。
- `test_stop_all_does_not_trigger_autoreconnect_when_profiles_have_autoReconnect`
  回归锁住 autoReconnect 跟 stopAll 的 race。
- `test_stop_all_preserves_error_and_stopped_tunnel_state` 回归锁住保留 .error /
  .stopped 诊断信息不被 stopAll 误清。

### Fixed
- **MenuBar popover 按钮点击无响应**:`.applicationDefined` + SwiftUI Button 在 NSPopover
  下 hit-test 不可靠(详见 `bdd42b7`)。换成 HStack + `.onTapGesture` 走 SwiftUI gesture
  系统;MenuBarItem / MenuBarProfileRow / Open Application / Settings… /
  Refresh SSH Config 这几个固定,Refresh 不再静默吞错(`do/catch`,DEBUG `print` 到 stderr)。
- **MenuBar popover 需点两下才生效**(老 bug,review 8 重审):`.applicationDefined` NSPopover
  的 NSPanel 默认不主动抢 key,第一次 click 被 AppKit 用做 key-window promotion。
  修法:加 `AutoKeyPopover: NSPopover` 子类,在 `show()` 后 `DispatchQueue.main.async`
  强制 `makeKey`,keyable HostingController 双保险;outsideClickMonitor 加 **300ms time-window swallow**
  应对 popover 刚开时的 burst event;AutoKeyPopover 覆盖 toolbar `show(relativeTo:)` 重载
  以防遗漏入口。
- **MenuBar popover 不响应 Escape** — `.applicationDefined` 替换 `.transient` 之后标准
  "按 Esc 关掉"消失。outsideClickMonitor matching 加 `.keyDown`,closure 识别
  `keyCode == 53` (kVK_Escape) → performClose。
- **MenuBar popover 点外面 / Settings 触发后 popover 不消失** — outsideClickMonitor 用
  window-identity 判断 + 时间窗 swallow 后,逻辑稳定;Settings / Open Application /
  Refresh SSH Config / Quit / Start All / Stop All 这几条路径里需要主动 dismiss 的
  改成调 `MenuBarController.dismissPopover()`(新加 helper,统一拆 monitor + 关 popover + 清
  swallowOutsideClickUntil 三件套)。
- **stopAll 后状态被 autoReconnect 误重连**:之前 `stopAll()` 漏 `userRequestedStop.insert`
  + 漏最终 `.stopped` 收尾。修法完全照搬 per-profile `stop(profileID:)` 的两步结构 — handleProcessExit
  见到 `userRequestedStop.remove(...)` 命中就 early-return + 不进 autoReconnect 分支。
- **stopAll 覆盖 .error / .stopped 诊断信息**(review #2):之前第二轮 loop 无差别写
  `lastError = nil`,把 .error tunnel 的 exit code / reason 全擦了,UI 看不到失败原因。
  改成只对活跃态(.running / .starting / .reconnecting / .stopping)收敛,history 保留。
- **stopAll 不覆盖 .reconnecting / .starting**(review #1):原来只在 `.running` 标 userRequestedStop,
  半路 .reconnecting 的 tunnel observation task 后续命中 .terminated 仍走"自然死"分支。
  改成对所有 ids 标记 + `await reconnectController.cancelAll()` 取消 in-flight schedule。
- **`userRequestedStop` Set 泄漏**(review #4):observation task 不发 .terminated 时(进程被
  外部 SIGKILL / 启动后立刻退出 / Fake 环境)Set 条目永远不清。下次 start() 后新 SSH 自然退出
  错命中这个 stale entry,tunnel 卡在 .running 但 SSH 已死。两道防御:1)
  `start(profileID:)` 入口显式 `userRequestedStop.remove(profileID)` 清残留;2)
  `handleProcessExit` 加 `alreadyFinalized` guard,state 已经是 .stopped 就跳过状态写入 + autoReconnect
  触发。
- **`scripts/release.sh` 默认占位签名**,改成读 env(`CODE_SIGN_IDENTITY` 等)。
- **`scripts/release.sh` zip 路径 bug**:`cd $BUILD_DIR` + `basename $APP_PATH` 拼成
  `<build>/JanusSSH.app`(实际在 `<build>/Build/Products/Release/JanusSSH.app`),ditto
  "Cannot get real path"。改成直接传绝对路径 + notarize 也用同样路径。
- **DMG 缺 volume icon**(macOS mount 后 Finder 显示白板 disk 图标):
  `hdiutil create -volicon` 在 macOS 26 已不再识别,改走 dmgbuild / `create-dmg` 同款流程 —
  可写中间 dmg + 拷 `.VolumeIcon.icns` 进根目录 + `SetFile -a C` 加 `kCustomIcon` flag,
  Finder 据此渲染 volume icon。
- **DMG 没有传正常的 app icon**:`Assets.xcassets/AppIcon.appiconset` 编译出来只含 `ic13`
  (256×256,体积 51KB),Finder sidebar 缩到小尺寸看着糊。从 asset catalog 拼 16/32/128/256/512 ×
  @1x/@2x 共 10 张 PNG,`sips` 拼 iconset 后 `iconutil -c icns` 编出 ~400KB 多尺寸 volicon。
- **来源 Info.plist `CFBundleShortVersionString` 写死 0.1.1**:`release.sh $VERSION` 只动 zip /
  DMG 文件名,产物 .app 的"关于"面板永远 0.1.1。修法:build 完后 plutil patch 产物的
  `Contents/Info.plist` + `codesign --force --sign` 重签(Info.plist 在 _CodeSignature 哈希里,
  改完必须重签让签名重新 hash 进去)。`CFBundleVersion` 从 `git rev-list --count HEAD` 取,
  跟 commit 数绑定。源 Info.plist 这次同步 bump 到 0.2.0 —— 一次正式 release 的产物。
- **make release 完整测试 target 编译错**:Swift 6 strict concurrency 下若干 pre-existing
  错误阻挡 `swift test` — ProfileValidatorTests `70000` 溢出 UInt16,Domain/ProfileTests
  `Behavior` 没带 namespace,SSHProcessTests `var stderrBytes` 在 @Sendable closure mutate,
  PortCheckerTests NSLock 不能在 async 调,TunnelManagerTests `TunnelManager` 是 @MainActor
  导致测试方法也得 @MainActor 等 11 处 pre-existing 错误。逐个收敛到 actor 或 sync 化以过 Swift 6。

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

[Unreleased]: https://github.com/lshgdut/janus-ssh/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/lshgdut/janus-ssh/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/lshgdut/janus-ssh/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/lshgdut/janus-ssh/releases/tag/v0.1.0
