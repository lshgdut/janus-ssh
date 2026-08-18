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
mkdir -p "$BUILD_DIR/dmg"
cp -R "$APP_PATH" "$BUILD_DIR/dmg/"
ln -s /Applications "$BUILD_DIR/dmg/Applications"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$BUILD_DIR/dmg" \
  -ov -format UDZO \
  "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo "✅ Release artifacts:"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.zip"
echo "  - $BUILD_DIR/$APP_NAME-$VERSION.dmg"