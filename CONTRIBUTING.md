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