#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

swift build

binary_path="$(swift build --show-bin-path)/PaperCodexApp"
app_path="${PAPER_CODEX_APP_PATH:-$HOME/Applications/PaperCodex.app}"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

rm -rf "$app_path"
mkdir -p "$(dirname "$app_path")"
mkdir -p "$macos_path" "$resources_path"
cp "$binary_path" "$macos_path/PaperCodexApp"

cat > "$contents_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>PaperCodexApp</string>
  <key>CFBundleIdentifier</key>
  <string>local.paper-codex.app</string>
  <key>CFBundleName</key>
  <string>Paper Codex</string>
  <key>CFBundleDisplayName</key>
  <string>Paper Codex</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$app_path"
