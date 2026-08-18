# JanusSSHTunnelEngine

Janus SSH 的 Tunnel Engine — 独立 Swift Package,可单独测试,不依赖 SwiftUI。

## 状态

**M1 — Domain Model**(完成 ✅)

实现:
- `Profile` — 持久化配置,与运行时解耦
- `PortForward` — `-L` 参数一行,带 `localEndpoint` / `sshArgument` 计算属性
- `Tunnel` — 运行时对象,持有 `ProfileSnapshot`(不可变副本)
- `ProfileSnapshot` — Tunnel 启动时拍下的快照
- `TunnelState` / `TerminationReason` — 状态机
- `TunnelError` — `Equatable` + `LocalizedError`
- `ProfileValidator` — 单 profile 校验 + 跨 profile 端口冲突

## 验证

### 在 Xcode 16+ 中(推荐)

```bash
xed JanusSSHTunnelEngine  # 打开 Xcode
# Cmd+U 跑 XCTest
```

或命令行:

```bash
swift test
```

### 在 CommandLineTools 中(本机当前环境)

由于 CommandLineTools 不携带 XCTest framework 且 SPM 不会自动链接 Swift Testing,
`swift test` 在当前机器上无法运行。`verify/verify.swift` 提供了不依赖任何测试框架的
独立可执行验证 — 它直接把 Domain API 当作程序入口调用。

```bash
swiftc -parse-as-library -o /tmp/janus_verify \
  Sources/JanusSSHTunnelEngine/Domain/*.swift \
  Sources/JanusSSHTunnelEngine/Validation/*.swift \
  verify/verify.swift

/tmp/janus_verify
```

预期输出:`Result: 31 passed, 0 failed`

## 依赖

- Swift 6.0+
- macOS 14+

## 架构定位

```
JanusSSH/                       ← macOS App target(SwiftUI)
└── depends on →
JanusSSHTunnelEngine/           ← 本 Package,纯 Swift
    Domain / Validation
```

未来可独立抽出 `janus` CLI 时,直接 import 本 Package 即可。