# ADR-0007: No App Sandbox

## Status

Accepted · 2026-08-18

## Context

macOS App Store 要求启用 `com.apple.security.app-sandbox`,但 Janus SSH 需要的能力和 Sandbox 不兼容。

## Decision

**不启用 App Sandbox** — `com.apple.security.app-sandbox` = `false`

## Rationale

Janus SSH 必须能:
1. **spawn `/usr/bin/ssh`** — Sandbox 限制只能 spawn entitlement 允许的 binary
2. **读 `~/.ssh/config`** — Sandbox 默认 sandbox 自己的 container
3. **访问 ssh-agent** — IPC 受限
4. **kill 任意子进程** — 包括 SSH 派生的 shell / proxy
5. **操作进程组** — Stop All 需要一次性清理所有 SSH 后代

这些全部在 Sandbox 限制下无法工作。

## Alternative Considered

| 方案 | 问题 |
|------|------|
| App Sandbox + 申请 ssh-auxiliary entitlement | Apple 不会批 |
| Helper App + XPC | MVP 不引入(ADR-0006) |
| 主 App 不用 Sandbox,通过 Helper 做受限操作 | 增加复杂度,延迟收益 |

## Security Compensation

由于不启用 Sandbox,启用 **Hardened Runtime** 全部限制:

```xml
<key>com.apple.security.cs.allow-jit</key>
<false/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<false/>
<key>com.apple.security.cs.disable-library-validation</key>
<false/>
<key>com.apple.security.cs.allow-dyld-environment-variables</key>
<false/>
```

+ **Notarization**:`xcrun notarytool submit` 公证
+ **签名**:`Developer ID Application`(非 App Store)

## Consequences

- **不能在 Mac App Store 上架**
- **Homebrew Cask / GitHub Release** 分发
- **首次启动需要右键"打开"绕过 Gatekeeper**(或公证后无此问题)