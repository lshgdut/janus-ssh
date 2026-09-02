## [0.3.1] - 2026-09-02

### 🐛 Bug Fixes

- 🐛 fix(xcodeproj): embed JanusSSHTunnelEngine framework in Contents/Frameworks

### ⚙️ Miscellaneous Tasks

- 🔖 chore(release): update CHANGELOG
- 🔖 chore(release): bump 源 Info.plist 0.2.0 → 0.3.0 + Makefile VERSION 默认
## [0.3.0] - 2026-09-01

### 🐛 Bug Fixes

- *(changelog)* Revert 1e78044 (CHANGELOG 误清空 cliff 跑空 commit)
- 🔧 fix(changelog): cliff filter_unconventional=false + body 截断
- 🐛 fix(release): 修 --bump "$VERSION" 让 git-cliff 报 invalid value
- 🐛 fix(tunnel): drop stale .terminated events across restart
- 🐛 fix(makefile): rename DMG mount var from 'MN T' to 'DMG_MNT'

### 💼 Other

- Bump softprops/action-gh-release from 2 to 3

### 📚 Documentation

- 📝 docs(changelog): 恢复 CHANGELOG.md 到 cliff auto 跑空前的 0.2.0 段

### 🎨 Styling

- 🎨 style(profile-editor): spacious padding + save lock + label column
- 🎨 style(profile-list): fixed-column forwards list

### ⚙️ Miscellaneous Tasks

- 🔖 chore(release): update CHANGELOG for 0.3.0
- 🔖 chore(release): update CHANGELOG
- 🔖 chore(release): update CHANGELOG for v0.3.0
## [0.2.0] - 2026-08-26

### 🐛 Bug Fixes

- 🐛 fix(popover): AutoKeyPopover 子类 + show() 后立刻调度 makeKey
- 🐛 fix(popover): SwiftUI Button 换成 .onTapGesture + swallow 打开那下 click
- 🐛 fix(popover): 时间窗 swallow + Settings/Refresh 自动 dismiss
- 🐛 fix(popover): Open Application 触发后也 dismiss popover
- 🔥 fix(debug): 移除 menu-bar-debug.log 临时日志
- 🐛 fix(tunnel): Stop All 应立刻把所有 tunnel 置 .stopped,不再被 autoReconnect 误重连
- 🐛 fix(tunnel): userRequestedStop Set 泄漏 #4 — 多加两道防御
- 🐛 fix(release): VERSION 参数真正改 .app 的 Info.plist,About 面板跟文件名对齐

### 📚 Documentation

- 📝 docs(release): ad-hoc DMG 配 RELEASE-README + install-unquarantine.command

### 🎨 Styling

- 🎨 style(profile-card): 把状态 pill 从右侧挪到 title 旁
- 💄 style(status-badge): halo 周期 2.6s + RadialGradient 软边 + clip 行
- 💄 style(status-badge): halo 范围 1.2→2.4(上一版调太紧)
- 💄 style(status-badge): halo 中心透明度 0.7 → 0.45

### 🧪 Testing

- ✅ test(engine): 加 stopAll autoReconnect 回归 + 修测试 target Swift 6 编译错

### ⚙️ Miscellaneous Tasks

- 🔧 chore(debug): 加 menu-bar-debug.log 临时日志
- 🔧 chore(build): 加 Makefile 暴露 release / dmg / dmg-quick / build / test / clean
- 🔖 chore(release): bump 源 Info.plist 0.1.1 → 0.2.0 + CHANGELOG.md 0.2.0 段
## [0.1.1] - 2026-08-25

### 🚀 Features

- *(profile-card)* 新增 PrimaryButtonStyle,Start 按钮对齐设计图
- *(profile-card)* 新增 SecondaryButtonStyle,Stop 按钮对齐设计图
- *(profile-card)* Error pill 文案按 TunnelError 智能推断
- 🎨 feat(ui): Settings 危险区 + MenuBar 设计还原
- 🎨 feat(ui): 主题切换 + 编辑器/菜单栏 UX 全套优化

### 🐛 Bug Fixes

- *(profile-card)* Retry 按钮去掉红色 tint,对齐设计图蓝色
- 🐛 fix(profile-card): Start/Retry/Stop 按钮无响应
- 🐛 fix(popover): 修 MenuBar popover 按钮要点两下才生效

### 💼 Other

- .gitignore 加 .superpowers/(sdd 进度台账)
- Profile Editor 持续重写 + SSH Tunnel Engine 调整

### ⚙️ Miscellaneous Tasks

- 🔖 chore(release): cut 0.1.1
## [0.1.0] - 2026-08-21

### 🚀 Features

- Initial Janus SSH implementation (M1-M10)
- 设计 Janus SSH App 图标
- SSH Hosts 页面重写 — 紧凑专业版
- SSH Hosts 测试结果在按钮上显示
- Profile Editor 全面重写 — 对齐 OpenDesign 设计图

### 🐛 Bug Fixes

- Sidebar navigation state sharing between SidebarView and DetailView
- SSHConfigParser 支持 Include 递归 / glob / 循环保护
- 移除 LSUIElement,让 App 显示在 Dock 和 Cmd+Tab
- 配置 ASSETCATALOG_COMPILER_APPICON_NAME 让 AppIcon.icns 生成
- Menu Bar 配色 + 图标适配系统 light/dark
- Menu Bar 图标统一为 Janus 双弧设计(单色 template)
- Profile Editor Forward 行 — 数字输入框左对齐 + FieldCell
- SSH Config 多 alias 展开 + hostname 回退到 alias
- 修复 NSXPCDecoder 警告 — MenuBarExtra 改用 .menu 模式
- Profile Editor 改用独立 Window + 加回 ProfileCard

### 💼 Other

- Add Xcode project for JanusSSH macOS app
- Complete macOS App build + DMG (v0.1.0)
- Gitignore *.dmg and build/ artifacts
- Optimize .gitignore — dedupe entries, organize by category
- Gitignore .claude/settings.local.json
