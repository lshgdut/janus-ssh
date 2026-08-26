# JanusSSH Makefile — build / release / DMG packaging
#
# 用法:make help
#
# 三个 build target:
#   release      — A 路径:跑 scripts/release.sh(完整 ad-hoc + Developer ID
#                   + 公证,KEYCHAIN_PROFILE gating)
#   dmg          — B 路径 1:手动 multi-step DMG,带 volicon + README + .command
#   dmg-quick    — B 路径 2:5 行 super fast DMG,只有 .app,无 volicon / README
#                   / .command
#
# 加上 build / test / clean 等常规 target。

# —— 变量 ——————————————————————————————————————————————————————
APP_NAME       := JanusSSH
SCHEME         := JanusSSH
PROJECT        := JanusSSH/JanusSSH.xcodeproj
ENGINE         := JanusSSHTunnelEngine
BUILD_DIR      := build
VERSION        ?= 0.1.1

# —— 默认 goal:help ——————————————————————————————————————————————
.PHONY: help
help:
	@echo "JanusSSH build commands:"
	@echo "  make build       Debug 编译(开发用,不产 DMG)"
	@echo "  make test        跑 engine 的 Swift 测试"
	@echo ""
	@echo "  make release     A 路径:跑 scripts/release.sh \$$VERSION,完整流程"
	@echo "                     (ad-hoc 默认 / Developer ID + 公证 export 三个 env)"
	@echo "  make dmg         B 路径 1:手动 multi-step DMG,带 volicon + README + .command"
	@echo "  make dmg-quick   B 路径 2:5 行 super fast,只装 .app(无 volicon / 文档)"
	@echo ""
	@echo "  make clean       清掉 build/ 目录"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=x.y.z               覆盖版本号(默认 \$$VERSION)"
	@echo "  CODE_SIGN_IDENTITY=...      Apple Developer ID 签名身份(默认 '-' 走 ad-hoc)"
	@echo "  DEVELOPMENT_TEAM=...        Apple 团队 ID(10 位)"
	@echo "  KEYCHAIN_PROFILE=...        notarytool 凭据 profile 名(启用真签 + 公证)"

# —— Build Debug —快速编译,不产 DMG ————————————————————————
.PHONY: build
build:
	xcodebuild \
	-project $(PROJECT) -scheme $(SCHEME) \
	-configuration Debug \
	-derivedDataPath $(BUILD_DIR) \
	-destination 'platform=macOS' \
	clean build

# —— Test 跑 engine 的 swift test ——————————————————————————
.PHONY: test
test:
	cd $(ENGINE) && swift test --filter "$(T)"

# —— A 路径:scripts/release.sh —完整 pipeline ——————————————
.PHONY: release
release:
	./scripts/release.sh $(VERSION)

# —— B 路径(Quick):5 行 super fast —————————————————————————
# 只装 .app 进 DMG,没有 volicon / 没有 README / 没有 install helper。
# 给"我就要快速打个包测一下"的本地调试用。
#
# 走 -srcfolder 所以是 UDRO(read-only)DMG — 不能改内部,不能补 volicon。
# 体积小,无任何 ad-hoc 用户辅助(供 Developer ID 路径使用就 OK)。
.PHONY: dmg-quick
dmg-quick:
	@echo "==> Building Release..."
	@xcodebuild \
	-project $(PROJECT) -scheme $(SCHEME) \
	-configuration Release \
	-derivedDataPath $(BUILD_DIR) \
	CODE_SIGN_IDENTITY=$${CODE_SIGN_IDENTITY:--} \
	CODE_SIGN_STYLE=Manual \
	clean build
	@APP=$$(find $(BUILD_DIR) -name "$(APP_NAME).app" -type d 2>/dev/null | head -1); \
	if [ -z "$$APP" ]; then \
	echo "❌ 没找到 $(APP_NAME).app — xcodebuild 失败?"; exit 1; \
	fi; \
	echo "Found: $$APP"; \
	echo "==> Bumping version to $(VERSION) in built .app..."; \
	APP_PLIST="$$APP/Contents/Info.plist"; \
	if [ -f "$$APP_PLIST" ]; then \
	  BUILD_NUM=$$(git rev-list --count HEAD 2>/dev/null || echo "1"); \
	  plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$$APP_PLIST"; \
	  plutil -replace CFBundleVersion -string "$$BUILD_NUM" "$$APP_PLIST"; \
	  echo "    - CFBundleShortVersionString = $(VERSION)"; \
	  echo "    - CFBundleVersion = $$BUILD_NUM"; \
	  codesign --force --sign - "$$APP" 2>/dev/null || true; \
	fi; \
	echo "==> Creating quick DMG (no volicon / no docs)..."; \
	mkdir -p $(BUILD_DIR); \
	hdiutil create -srcfolder "$$APP" \
	-volname "$(APP_NAME)" \
	-ov -format UDZO \
	$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-quick.dmg; \
	echo ""; \
	echo "✅ $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-quick.dmg"

# —— B 路径(Advanced):手动 multi-step DMG ——————————————————
# 等价 scripts/release.sh 的 ad-hoc 分支,但完全 inline,
# 不依赖任何环境变量凭据。
# 嵌 .VolumeIcon.icns + Resources/RELEASE-README.md + Resources/
# install-unquarantine.command 三件套。
#
# 跟 release.sh 的差别:这个 target 始终走 ad-hoc — 真签 / 公证该走
# `make release` + 显式 export。dev 阶段这两套并存:release 跑正式 pkg,
# dmg 跑临时调试包。
.PHONY: dmg
dmg:
	@echo "==> Building Release..."
	@xcodebuild \
	-project $(PROJECT) -scheme $(SCHEME) \
	-configuration Release \
	-derivedDataPath $(BUILD_DIR) \
	CODE_SIGN_IDENTITY=$${CODE_SIGN_IDENTITY:--} \
	CODE_SIGN_STYLE=Manual \
	clean build
	@APP=$$(find $(BUILD_DIR) -name "$(APP_NAME).app" -type d 2>/dev/null | head -1); \
	if [ -z "$$APP" ]; then \
	echo "❌ 没找到 $(APP_NAME).app — xcodebuild 失败?"; exit 1; \
	fi; \
	echo "App: $$APP"; \
	echo "==> Bumping version to $(VERSION) in built .app..."; \
	APP_PLIST="$$APP/Contents/Info.plist"; \
	if [ -f "$$APP_PLIST" ]; then \
	  BUILD_NUM=$$(git rev-list --count HEAD 2>/dev/null || echo "1"); \
	  plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$$APP_PLIST"; \
	  plutil -replace CFBundleVersion -string "$$BUILD_NUM" "$$APP_PLIST"; \
	  echo "    - CFBundleShortVersionString = $(VERSION)"; \
	  echo "    - CFBundleVersion = $$BUILD_NUM"; \
	  codesign --force --sign - "$$APP" 2>/dev/null || true; \
	fi; \
	echo "==> Building volicon..."; \
	ICONSET="$(BUILD_DIR)/volicon.iconset"; \
	mkdir -p $$ICONSET; \
	ICONSET_SRC="$(CURDIR)/JanusSSH/Resources/Assets.xcassets/AppIcon.appiconset"; \
	for f in "16 16 icon_16x16" "32 32 icon_16x16@2x" "32 32 icon_32x32" \
	"64 64 icon_32x32@2x" "128 128 icon_128x128" "256 256 icon_128x128@2x" \
	"256 256 icon_256x256" "512 512 icon_256x256@2x" "512 512 icon_512x512" \
	"1024 1024 icon_512x512@2x"; do \
	set -- $$f; \
	sips -z $$1 $$2 "$$ICONSET_SRC/$$3.png" --out "$$ICONSET/$$3.png" >/dev/null; \
	done; \
	VOLICON="$(BUILD_DIR)/volicon.icns"; \
	iconutil -c icns $$ICONSET -o $$VOLICON; \
	echo "==> Creating writable HFS+ DMG..."; \
	SIZE=$$(($$(du -sk "$$APP" | awk '{print $$1}') + 51200))k; \
	hdiutil create -size $$SIZE -fs HFS+ \
	-volname "$(APP_NAME) $(VERSION)" -ov \
	"$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"; \
	echo "==> Embedding app + docs + volicon..."; \
	MN T=$$(mktemp -d); \
	hdiutil attach -nobrowse -mountpoint $$MN T \
	"$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg" >/dev/null 2>&1 && (\
	cp -R "$$APP" "$$MN T/" && \
	ln -s /Applications "$$MN T/Applications" && \
	cp "$(CURDIR)/Resources/RELEASE-README.md" "$$MN T/" 2>/dev/null && \
	cp "$(CURDIR)/Resources/install-unquarantine.command" "$$MN T/" 2>/dev/null && \
	chmod +x "$$MN T/install-unquarantine.command" 2>/dev/null && \
	cp $$VOLICON "$$MN T/.VolumeIcon.icns" && \
	SetFile -a C "$$MN T/.VolumeIcon.icns" && \
	SetFile -a C "$$MN T" && \
	hdiutil detach $$MN T >/dev/null; \
	); \
	rmdir $$MN T; \
	rm -rf $$ICONSET $$VOLICON; \
	echo "==> Compressing to UDZO..."; \
	hdiutil convert "$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg" -format UDZO -ov \
	-o "$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-UDZO.dmg"; \
	mv "$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-UDZO.dmg" \
	"$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"; \
	echo ""; \
	echo "✅ $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"; \
	ls -la "$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"

# —— Clean 清掉 build/ ——————————————————————————————————————
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	@echo "✓ cleared $(BUILD_DIR)/"

.DEFAULT_GOAL := help
.PHONY: all build test release dmg dmg-quick clean
