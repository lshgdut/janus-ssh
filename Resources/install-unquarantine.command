#!/bin/bash
# JanusSSH Install Helper — 去掉 macOS Gatekeeper 的 quarantine 标记
#
# JanusSSH 当前以 ad-hoc 签名分发(无 Apple Developer ID),从 DMG 拖到
# /Applications 后首次打开会被 Gatekeeper 拦,显示"已损坏,无法打开"。
# 这个脚本去掉 app 上的 com.apple.quarantine 标记,等同用户在 Finder 右键
# "Open" 一次。
#
# 用法:
#   1. 把 JanusSSH.app 拖到 /Applications
#   2. 双击 install-unquarantine.command(或在 Terminal 跑:
#      bash install-unquarantine.command)
#
# 这个脚本是幂等的 — 没标 quarantine 也不报错。

set -euo pipefail

APP="/Applications/JanusSSH.app"

if [ ! -d "$APP" ]; then
    cat <<EOF
❌ 找不到 $APP

先把 JanusSSH.app 从 DMG 拖到 /Applications,再跑这个脚本。
EOF
    exit 1
fi

# xattr -p 检查属性存在,没标 quarantine 会 exit 1。
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$APP"
    echo "✅ 已去掉 $APP 的 quarantine 标记"
else
    echo "ℹ️  $APP 没有 quarantine 标记,跳过"
fi

echo ""
echo "现在可以启动 JanusSSH 了:"
echo "  open $APP"
echo "或在 Finder 双击 /Applications/JanusSSH.app"
echo ""

read -r -p "现在打开?(Y/n) " ans
case "${ans:-Y}" in
    [Yy]*) open "$APP" ;;
    *) echo "好的,稍后自己开。Bye!" ;;
esac
