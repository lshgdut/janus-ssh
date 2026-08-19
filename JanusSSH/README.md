# Janus SSH - macOS App

macOS App target. **需要 Xcode 16+** 才能 build。

## 在 Xcode 中打开

```bash
xed .
```

Xcode 会自动:
1. 解析 `JanusSSH.xcodeproj`
2. 关联 `../JanusSSHTunnelEngine` 作为本地 Swift Package
3. 编译 15 个 Swift 文件 + Info.plist + entitlements

## 不需要完整 Xcode 时

打开本目录的两种方式:
- `xed .` → 完整 IDE
- `open JanusSSH.xcodeproj` → 只打开工程

## 第一个 build 失败的常见原因

| 报错 | 解决 |
|------|------|
| "missing Xcode" | 装 Xcode 16+ |
| "no provisioning profile" | 工程默认 `CODE_SIGNING_REQUIRED=NO`,本地无需证书 |
| "module JanusSSHTunnelEngine not found" | File → Packages → Resolve Package Versions |

## 工程结构

```
JanusSSH/
├── App/                    # 5 文件 — 生命周期 + DI 容器 + App entry
│   ├── JanusSSHApp.swift
│   ├── AppContainer.swift
│   ├── AppLifecycleManager.swift
│   ├── SSHHostManager.swift
│   ├── SettingsManager.swift
│   └── NotificationManager.swift
├── Presentation/
│   ├── Navigation/         # RootView, SidebarView
│   ├── Profiles/           # ProfileListView, ProfileEditorView, ProfileRunningView
│   ├── Hosts/              # SSHHostListView
│   ├── Logs/               # TunnelLogView
│   ├── Settings/           # SettingsView
│   └── MenuBar/            # MenuBarView
└── Resources/
    ├── Info.plist          # LSUIElement=true (不在 Dock)
    └── JanusSSH.entitlements # Sandbox=OFF + Hardened Runtime
```

## 打包 DMG

在 Xcode 中 Product → Archive → Distribute App → Developer ID → 自动 notarize。

或命令行(需 Developer ID):

```bash
xcodebuild -project JanusSSH.xcodeproj \
  -scheme JanusSSH \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  archive

xcodebuild -exportArchive \
  -archivePath build/Build/Products/Release/JanusSSH.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist ExportOptions.plist
```
