# Contributing to Janus SSH

欢迎贡献!在开始之前,请阅读以下指南。

---

## 开发环境

- **macOS 14+**(必需)
- **Xcode 16+**(推荐,用于 SwiftUI / App 调试)
- **Swift 6.0+**
- **Docker**(可选,用于集成测试)

---

## 仓库结构

```
janus-ssh/
├── JanusSSHTunnelEngine/    # 独立 Swift Package(可单独开发测试)
├── JanusSSH/                 # macOS App (Xcode project)
├── docs/                     # 架构 + ADR
├── scripts/                  # 构建 / 发布脚本
├── tools/                    # 集成测试 fixtures
└── homebrew/                 # Cask 模板
```

---

## 工作流

1. **Fork + Branch**:从 `main` 拉 `feature/xxx` 分支
2. **TDD**:先写测试,看它失败,再写实现
3. **跑测试**:`bash scripts/test.sh` 跑 verify(57 assertions)
4. **Lint**:可选 `swiftformat .`(配置见 `.swiftformat`)
5. **Commit**:`feat(scope): ...` / `fix(scope): ...` / `docs: ...`
6. **Push + PR**:CI 自动跑 macOS 14/15/26 三版本测试

---

## 提交信息规范

基于 [Conventional Commits](https://www.conventionalcommits.org/)。

```
feat(engine): add SSHConfigProviding.testConnection
fix(ssh): fix waitForExit termination handler race
docs(adr): add ADR-0010 ssh -G resolution
test(validator): add cross-profile port conflict
refactor(domain): extract ProfileSnapshot init
```

---

## 代码风格

- **Swift 6 strict concurrency**(actor / Sendable / async)
- **4 空格缩进**(`.editorconfig`)
- **120 字符行宽**
- **LF 换行**
- **不要 force unwrap**(除非在 init 中显式安全)
- **不要 zombie code**(没有用到的类型/函数删除)

---

## 添加新 ADR

如果做了重要架构决策:

1. `docs/adr/NNNN-short-name.md`(下一个序号)
2. 模板:
```markdown
# ADR-NNNN: <Title>

## Status
Proposed / Accepted / Deprecated

## Context
<背景>

## Decision
<决定>

## Consequences
### Positive
### Negative

## Alternatives Considered

## Notes
```

---

## 跑集成测试

```bash
cd tools/integration-tests
docker compose up -d
sleep 5
bash ../../scripts/integration-test.sh
docker compose down
```

---

## 发布流程(仅 Maintainer)

1. 更新 `CHANGELOG.md`
2. `git tag v0.x.y`
3. `git push --tags` 触发 `.github/workflows/release.yml`
4. GitHub Action 自动 build + sign + notarize + DMG + 更新 Homebrew Cask

---

## Sharing Ad-hoc Builds(给真人用户用)

`scripts/release.sh` 默认是 **ad-hoc 签名**(`CODE_SIGN_IDENTITY=-`),
**没有 Apple Developer ID 也没有公证**。这个模式下产出的 DMG:

- 本机跑 OK,自己 debug 用
- **给真人用会被 macOS Gatekeeper 拦**:`"JanusSSH" 已损坏,无法打开`

构建出的 DMG 里有两份给最终用户的辅助:

| 文件 | 作用 |
|---|---|
| `RELEASE-README.md` | 在 DMG 内,安装步骤 + ad-hoc 说明,Quick Look / Finder 直接显示 |
| `install-unquarantine.command` | 在 DMG 内,双击在 Terminal 跑,去掉 `com.apple.quarantine` 标记(等同 Finder 右键 Open) |

两条路径之一就够了,最终用户用脚本里的 "方法 A — 跑这个 DMG 自带的 `install-unquarantine.command`" 最省事。

### 真发出去(走 Apple Developer ID)

`scripts/release.sh` 已经为切到 Developer ID 流程做了准备,export 三个
env 即可整链路签名 + 公证:

```bash
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name"
export DEVELOPMENT_TEAM="YOUR10DIGITTEAMID"
export KEYCHAIN_PROFILE="JanusSSH-Notarize"  # 用 `xcrun notarytool store-credentials` 一次性配
./scripts/release.sh 0.2.0
```

脚本里 `KEYCHAIN_PROFILE` gating 已经在了:无值跳过 notarize(本机 ad-hoc),
有值走完整真签 + notarize + staple。Developer ID 用户的
`install-unquarantine.command` 在脚本里自动检测到无 quarantine 是 no-op,
所以正式分发的 DMG 里这俩文档保留着也无害。

需要 Apple Developer ID 时:https://developer.apple.com/programs/ (¥649/年)

### 一次性的 `.command` 信任

首次跑 `install-unquarantine.command` macOS 自己的 Gatekeeper 也会拦
(`.command` 不像已签名的 `.app`)。第一次用户在 Finder 里右键 → Open
→ Open 一次,之后双击就行。或者 `xattr -d com.apple.quarantine` 一次。