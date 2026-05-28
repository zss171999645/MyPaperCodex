#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PAPER_CODEX_OBSIDIAN_VAULT_ROOT="${PAPER_CODEX_OBSIDIAN_VAULT_ROOT:-/Users/horizon/Documents/Obsidian-Main/世界模型}"
export PAPER_CODEX_SUPPORT_ROOT="${PAPER_CODEX_SUPPORT_ROOT:-$repo_root/.papercodex-obsidian}"

cd "$repo_root"
swift build -c release --product PaperCodexApp

bin_path="$(swift build -c release --show-bin-path)"
app_bundle="$repo_root/.build/PaperCodexApp.app"
app_binary="$app_bundle/Contents/MacOS/PaperCodexApp"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$bin_path/PaperCodexApp" "$app_binary"

cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>PaperCodexApp</string>
  <key>CFBundleIdentifier</key>
  <string>local.papercodex.obsidian</string>
  <key>CFBundleName</key>
  <string>PaperCodex</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

exec "$app_binary"
