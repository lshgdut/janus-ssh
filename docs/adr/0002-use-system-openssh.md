# ADR-0002: 100% Use System OpenSSH

## Status

Accepted · 2026-08-18

## Context

Janus SSH 需要启动 SSH Tunnel,有两种选择:

**Option A**: 自己实现 SSH 协议(类似 libssh2)
**Option B**: spawn 系统 `/usr/bin/ssh`

## Decision

采用 **Option B** — Janus SSH 不实现 SSH,100% 复用系统 OpenSSH。

## Consequences

### Positive

- **零 SSH 协议代码**:不维护 OpenSSH 兼容性的负担
- **自动支持所有 SSH 特性**:ProxyJump, ProxyCommand, IdentityFile, ssh-agent, Match, Include — OpenSSH 支持的我们都支持
- **macOS 自带**:不需要打包 OpenSSH,体积小
- **安全更新由 Apple 提供**:SSH 漏洞修复走 OS update
- **`ssh -G` 复用**:Host 解析让 OpenSSH 自己算,避免重复实现配置语义

### Negative

- **依赖 OpenSSH 位置**:`/usr/bin/ssh` 在 macOS 上是稳定路径,但理论上 Apple 可能改
- **无法实现 OpenSSH 没有的特性**:例如自定义协议
- **跨平台困难**:Windows / Linux 路径不同 — MVP 不考虑

## Key Invariants

1. `SSHCommandBuilder.mandatoryFlags` 不可配置,必须包含:
   - `-N` (no tty)
   - `-o ExitOnForwardFailure=yes`
   - `-o BatchMode=yes`
   - `-o StrictHostKeyChecking=accept-new`

2. argv 数组直接传给 Process,**绝不**经过 shell:
   ```
   process.arguments = cmd.arguments   // ✓
   process.launchPath = "/bin/sh -c ssh ..."  // ✗
   ```

3. Host 解析通过 `ssh -G <alias>`,把 OpenSSH 当作 parser:
   ```
   ssh -G production
   user root
   hostname 10.10.0.10
   port 22
   ...
   ```

## Notes

未来如果要支持 `-R` (RemoteForward) 或 `-D` (DynamicForward),SSH 协议本身不需要重新实现 — 只需要扩展 `PortForward` 类型和 `SSHCommandBuilder.build`。