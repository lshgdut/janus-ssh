#!/bin/bash
# scripts/release.sh — 构建 + 签名 + 公证 + DMG
set -e

VERSION="${1:-0.1.1}"
APP_NAME="JanusSSH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"

echo "==> Building $APP_NAME $VERSION..."

# 1. Build Release
# 默认 ad-hoc signing(-身份,无需 Developer ID),让本机 / CI 都能跑通。
# 真发布时 export 三个 env 覆盖:
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name" \
#   CODE_SIGN_STYLE=Manual \
#   DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
#   KEYCHAIN_PROFILE="JanusSSH-Notarize" \
#   ./scripts/release.sh 0.2.0
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Manual}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
SIGN_FLAGS=()
SIGN_FLAGS+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
SIGN_FLAGS+=(CODE_SIGN_STYLE="$CODE_SIGN_STYLE")
if [ -n "$DEVELOPMENT_TEAM" ]; then
  SIGN_FLAGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

xcodebuild \
  -project "$ROOT/JanusSSH/JanusSSH.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  "${SIGN_FLAGS[@]}" \
  clean build

echo "==> Locating built .app..."
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)

# 2. Zip
# 1.5 Embed Swift Package frameworks into the .app
# xcodebuild 把 Swift Package 的 .framework 产物放在
#   Build/Products/Release/PackageFrameworks/<Name>.framework
# 但这个项目缺一个 "Embed Frameworks" build phase,所以 .app 里
# Contents/Frameworks/ 是空的。主 binary 的 rpath 是
#   @executable_path/../Frameworks
# 直接装到 /Applications 后 dyld 会找不到 framework,所有跨模块符号
# (例如 TunnelManager.init)都报 "Symbol missing",App 一启动就崩。
# 这里手动把 framework 拷进 .app/Contents/Frameworks/ 并重新签名,
# 让 .app 自包含、可以脱离打包机分发。
# 用 ditto 而不是 cp -R,保留 xattrs + codesign 签名。
FRAMEWORKS_SRC="$BUILD_DIR/Build/Products/Release/PackageFrameworks"
if [ -d "$FRAMEWORKS_SRC" ]; then
  echo "==> Embedding Swift Package frameworks..."
  mkdir -p "$APP_PATH/Contents/Frameworks"
  for fw in "$FRAMEWORKS_SRC"/*.framework; do
    [ -d "$fw" ] || continue
    base="$(basename "$fw")"
    echo "    - $base"
    ditto "$fw" "$APP_PATH/Contents/Frameworks/$base"
    # Embedded framework 必须跟主 app 用同一签名身份 — xcodebuild 在
    # Release + EnablePreviews 下不会自动重签嵌入产物,这里手动补。
    # Developer ID Application 形式跟 xcodebuild 同名即可。
    if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
      codesign --force --sign "$CODE_SIGN_IDENTITY" \
        --options runtime --timestamp=none \
        "$APP_PATH/Contents/Frameworks/$base" 2>/dev/null || true
    fi
  done
fi

echo "==> Bumping $APP_NAME to $VERSION in built .app..."
# Info.plist 里 CFBundleShortVersionString 在源文件写死(0.1.1)—— xcodebuild
# 不会替我们改 VERSION,产物 .app 里"关于"面板跟 .dmg 文件名对不上。
# 直接 patch build 出来的 .app/Contents/Info.plist(不动源文件 — 那是仓库的
# 事实,下一次 dev build 还得是 0.1.1 + 待 commit 的 bump)。
# 同时 bump build number(CFBundleVersion)—— commit 次数 +1,跟 DMG 文件名解耦。
APP_PLIST="$APP_PATH/Contents/Info.plist"
if [ -f "$APP_PLIST" ]; then
  BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo "1")
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PLIST"
  plutil -replace CFBundleVersion -string "$BUILD_NUM" "$APP_PLIST"
  echo "    - CFBundleShortVersionString = $VERSION"
  echo "    - CFBundleVersion = $BUILD_NUM"
  # Info.plist 被 _CodeSignature/CodeResources 哈希锁定 — 改完必须 re-sign,
  # 否则 codesign --verify 失败、Gatekeeper 拒签。
  if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp \
      "$APP_PATH" 2>/dev/null || true
  else
    # ad-hoc 路径,不必 timestamp/runtime,但 force 重签让 _CodeSignature
    # 重新 hash Info.plist
    codesign --force --sign - "$APP_PATH" 2>/dev/null || true
  fi
fi

echo "==> Zipping..."
# 用绝对路径,$APP_PATH 已经是 find 拿到的完整路径 — 之前 cd $BUILD_DIR + basename
# 会拼成 "<build>/JanusSSH.app",但 .app 实际在
# "<build>/Build/Products/Release/JanusSSH.app",ditto 报 "Cannot get real path"。
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$BUILD_DIR/$APP_NAME-$VERSION.zip"

# 3. Notarize — 只在 KEYCHAIN_PROFILE 已设置时跑。
# 默认(ad-hoc 本地构建)跳过 — 没有 Apple notary 凭据,且 ad-hoc 产物也
# 本来就需要 notarization 才能分发给用户。真发布前 export KEYCHAIN_PROFILE
# 即可激活这条路径。
if [ -n "${KEYCHAIN_PROFILE:-}" ]; then
  echo "==> Submitting for notarization (profile: $KEYCHAIN_PROFILE)..."
  xcrun notarytool submit "$BUILD_DIR/$APP_NAME-$VERSION.zip" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

  # 4. Staple
  echo "==> Stapling notarization ticket..."
  xcrun stapler staple "$APP_PATH"
else
  echo "==> Skipping notarization (KEYCHAIN_PROFILE not set; ad-hoc local build)"
fi

# 5. DMG
echo "==> Building DMG..."

# Build a proper volume icon — asset-catalog 生成的 AppIcon.icns 在 macOS 26 只含
# ic13(256×256),Mac OS Extended/HFS+ 的 volume icon 需要更完整的尺寸(ic07/ic08/.../ic14)
# 才能在 Finder sidebar / 桌面各种分辨率下都显示干净。从 asset catalog 的源码 PNG 拼一个
# 完整 iconset,再 iconutil 编成 icns。
VOLICON="$BUILD_DIR/VolumeIcon.icns"
ICONSET="$BUILD_DIR/VolumeIcon.iconset"
mkdir -p "$ICONSET"
ICONSET_SRC="$ROOT/JanusSSH/Resources/Assets.xcassets/AppIcon.appiconset"
sips -z 16 16    "$ICONSET_SRC/icon_16x16.png"          --out "$ICONSET/icon_16x16.png"          > /dev/null
sips -z 32 32    "$ICONSET_SRC/icon_16x16@2x.png"       --out "$ICONSET/icon_16x16@2x.png"       > /dev/null
sips -z 32 32    "$ICONSET_SRC/icon_32x32.png"          --out "$ICONSET/icon_32x32.png"          > /dev/null
sips -z 64 64    "$ICONSET_SRC/icon_32x32@2x.png"       --out "$ICONSET/icon_32x32@2x.png"       > /dev/null
sips -z 128 128  "$ICONSET_SRC/icon_128x128.png"        --out "$ICONSET/icon_128x128.png"        > /dev/null
sips -z 256 256  "$ICONSET_SRC/icon_128x128@2x.png"     --out "$ICONSET/icon_128x128@2x.png"     > /dev/null
sips -z 256 256  "$ICONSET_SRC/icon_256x256.png"        --out "$ICONSET/icon_256x256.png"        > /dev/null
sips -z 512 512  "$ICONSET_SRC/icon_256x256@2x.png"     --out "$ICONSET/icon_256x256@2x.png"     > /dev/null
sips -z 512 512  "$ICONSET_SRC/icon_512x512.png"        --out "$ICONSET/icon_512x512.png"        > /dev/null
sips -z 1024 1024 "$ICONSET_SRC/icon_512x512@2x.png"   --out "$ICONSET/icon_512x512@2x.png"     > /dev/null
iconutil -c icns "$ICONSET" -o "$VOLICON"
rm -rf "$ICONSET"

# 不能用 `hdiutil create -srcfolder`:
#   - `-srcfolder` 产出的 dmg 是 read-only(UDRO),后续无法写 .VolumeIcon.icns 进去
#   - macOS 26 的 `hdiutil create` / `convert` 都没了 -volicon flag
# 走 dmgbuild / `create-dmg` 同款流程:
#   1) 建一个 **可写** 中间 dmg(HFS+),2) mount 写内容 + 拷 .VolumeIcon.icns,
#   3) SetFile -a C 给 .VolumeIcon.icns 加 kCustomIcon flag(Finder 据此识别为 volume icon),
#   4) detach,5) 转成压缩 UDZO。最终 dmg 体积小,volume icon 显示正常。
#
# 取 dmg 大小 — .app 体积 + 50MB headroom,向上取整。
APP_BYTES=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_KB=$((APP_BYTES + 51200))
DMG_SIZE="${DMG_KB}k"

hdiutil create -size "$DMG_SIZE" -fs HFS+ -volname "$APP_NAME $VERSION" -ov \
  "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

MOUNT_POINT=$(mktemp -d)
if hdiutil attach -nobrowse -mountpoint "$MOUNT_POINT" \
    "$BUILD_DIR/$APP_NAME-$VERSION.dmg" >/dev/null 2>&1; then
  cp -R "$APP_PATH" "$MOUNT_POINT/"
  ln -s /Applications "$MOUNT_POINT/Applications"

  # 嵌入 ad-hoc 用户拿走的辅助:安装说明 + Gatekeeper 解除脚本。正式走
  # Developer ID + 公证的产物里这俩文档可以保留(无害),或者从 release 包里
  # 抽走 — 但做了下不去除,多 2 个文件无害。脚本里没强制区分 ad-hoc 跟签名
  # 路径,简化逻辑:Dev ID 用户的"双击 install-unquarantine.command"是 no-op
  # (脚本自动检测),所以不会误伤正式分发的体验。
  if [ -f "$ROOT/Resources/RELEASE-README.md" ]; then
    cp "$ROOT/Resources/RELEASE-README.md" "$MOUNT_POINT/RELEASE-README.md"
  fi
  if [ -f "$ROOT/Resources/install-unquarantine.command" ]; then
    cp "$ROOT/Resources/install-unquarantine.command" "$MOUNT_POINT/install-unquarantine.command"
    chmod +x "$MOUNT_POINT/install-unquarantine.command"
  fi

  # Volume icon — 设 .VolumeIcon.icns 到根目录 + 用 SetFile -a C 加 kCustomIcon flag。
  # 这个 flag 写在 com.apple.FinderInfo xattr 里,Finder 看到 .VolumeIcon.icns 文件
  # 跟 kCustomIcon 的元数据组合,就把这个 icns 渲染成 volume 的图标。
  cp "$VOLICON" "$MOUNT_POINT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_POINT/.VolumeIcon.icns"
  # 同时给 volume 根目录也加 custom-icon flag — 部分 macOS 版本需要这个双写,
  # 才能在 Finder sidebar 正确显示 mounted volume icon。
  SetFile -a C "$MOUNT_POINT"

  hdiutil detach "$MOUNT_POINT" >/dev/null
  rmdir "$MOUNT_POINT"
fi

hdiutil convert "$BUILD_DIR/$APP_NAME-$VERSION.dmg" -format UDZO -ov \
  -o "$BUILD_DIR/$APP_NAME-$VERSION-UDZO.dmg"
mv "$BUILD_DIR/$APP_NAME-$VERSION-UDZO.dmg" "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

rm -f "$VOLICON"

echo ""

# 6. CHANGELOG.md — git-cliff 接管,从 Conventional Commits 自动生成。
#    真发版用 `git cliff --tag v$VERSION..HEAD` 写盘 + commit;
#    本脚本默认不动 CHANGELOG.md(`--tag v$PREV..HEAD --bump`) 免得
#    跟人手工编辑的 CHANGELOG 冲突。如果环境明确设了
#    `UPDATE_CHANGELOG=1` 才走 auto-write — 跟 docs/release 文档里
#    "Maintainer releases" 步骤的 hard rule "1. 更新 CHANGELOG.md"
#    一致:默认 maintainer 手动维护,auto 只在显式要求时介入。
if [ "${UPDATE_CHANGELOG:-0}" = "1" ]; then
  echo "==> Regenerating CHANGELOG.md via git-cliff..."
  if ! command -v git-cliff >/dev/null 2>&1; then
    echo "⚠️  git-cliff not installed; skipping CHANGELOG auto-update"
  else
    PREV_TAG=$(git describe --tags --abbrev=0 "HEAD^" 2>/dev/null || true)
    if [ -z "$PREV_TAG" ]; then
      echo "⚠️  no previous tag found; can't compute range"
    else
      git cliff --tag "$PREV_TAG..HEAD" --bump "$VERSION" --topo-order \
        > CHANGELOG.md
      git add CHANGELOG.md
      if ! git diff --cached --quiet -- CHANGELOG.md; then
        git commit -m "🔖 chore(release): update CHANGELOG for v$VERSION"
      fi
      echo "    CHANGELOG.md updated for v$VERSION"
    fi
  fi
fi

echo ""
echo "✅ Release artifacts:"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.zip"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.dmg"