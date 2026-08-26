# JanusSSH — 安装说明

把 `JanusSSH.app` 拖到右边的 `/Applications` 文件夹,然后按下面顺序操作。

## 1. 安装(从 DMG 到 Applications)

把这个 DMG 里的 `JanusSSH.app` 拖到 `/Applications` 文件夹。

## 2. 解除 macOS Gatekeeper 拦截(只针对 ad-hoc 构建)

> **如果你看到这个 DMG 是 ad-hoc 签名分发的**(本 README 旁边有没有
> `install-unquarantine.command` 文件,看那个),首次打开会被 Gatekeeper
> 拦,显示"已损坏,无法打开"。两种办法任选其一:
>
> **方法 A — 跑这个 DMG 自带的 `install-unquarantine.command`**(推荐)
> 1. 双击 `install-unquarantine.command`,Terminal 会自动打开
> 2. 按提示回车确认即可
>
> **方法 B — 命令行**
> ```bash
> xattr -dr com.apple.quarantine /Applications/JanusSSH.app
> ```
>
> **方法 C — Finder 右键 Open 一次**
> 在 Finder 里对 `JanusSSH.app` 右键 → Open → 弹窗点 Open。

## 3. 启动

- 双击 `/Applications/JanusSSH.app`,或在终端 `open /Applications/JanusSSH.app`
- 第一次启动 macOS 会问网络 / 文件权限,选同意
- menu bar 出现 Janus 图标,点开看状态

## 这个包为什么是 ad-hoc 签名?

这个 DMG 没走 Apple Developer ID + 公证流程,签名是 macOS 自动生成本机的
ad-hoc 签名(`CODE_SIGN_IDENTITY=-`)。所以:

- **不打算分发给真人用户** → ad-hoc 直接用,OK
- **打算正式发布给他人 / 上 Mac App Store** → 需要 Apple Developer Program
  账号($99/年)+ Developer ID 证书 + Apple 公证。详细见 `CONTRIBUTING.md`
  的"Sharing Ad-hoc Builds"章节。

## 反馈

Bug / 建议:https://github.com/lshgdut/janus-ssh/issues
