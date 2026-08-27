## [0.1.1] - 2026-08-27

### 🐛 Bug Fixes

- *(changelog)* Revert 1e78044 (CHANGELOG 误清空 cliff 跑空 commit)
## [0.1.1] - 2026-08-27

### 🚀 Features

- *(profile-card)* 新增 PrimaryButtonStyle,Start 按钮对齐设计图
- *(profile-card)* 新增 SecondaryButtonStyle,Stop 按钮对齐设计图
- *(profile-card)* Error pill 文案按 TunnelError 智能推断

### 🐛 Bug Fixes

- *(profile-card)* Retry 按钮去掉红色 tint,对齐设计图蓝色

### 💼 Other

- .gitignore 加 .superpowers/(sdd 进度台账)
- Profile Editor 持续重写 + SSH Tunnel Engine 调整
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
