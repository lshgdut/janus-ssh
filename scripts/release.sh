#!/bin/bash
# scripts/release.sh — 构建 + 签名 + 公证 + DMG
set -e

VERSION="${1:-0.1.0}"
APP_NAME="JanusSSH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"

echo "==> Building $APP_NAME $VERSION..."

# 1. Build Release
xcodebuild \
  -project "$ROOT/JanusSSH.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="Developer ID Application: Joe" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  clean build

echo "==> Locating built .app..."
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)

# 2. Zip
echo "==> Zipping..."
cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$(basename $APP_PATH)" "$APP_NAME-$VERSION.zip"

# 3. Notarize
echo "==> Submitting for notarization..."
xcrun notarytool submit "$APP_NAME-$VERSION.zip" \
  --keychain-profile "JanusSSH-Notarize" \
  --wait

# 4. Staple
xcrun stapler staple "$APP_PATH"

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
echo "✅ Release artifacts:"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.zip"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.dmg"