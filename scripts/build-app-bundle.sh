#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${PAPER_CODEX_BUILD_CONFIGURATION:-release}"

swift build -c "$configuration"

binary_path="$(swift build -c "$configuration" --show-bin-path)/PaperCodexApp"
app_path="${PAPER_CODEX_APP_PATH:-$HOME/Applications/PaperCodex.app}"
bundle_identifier="${PAPER_CODEX_BUNDLE_IDENTIFIER:-local.paper-codex.app}"
codesign_identity="${PAPER_CODEX_CODESIGN_IDENTITY:--}"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

rm -rf "$app_path"
mkdir -p "$(dirname "$app_path")"
mkdir -p "$macos_path" "$resources_path"
cp "$binary_path" "$macos_path/PaperCodexApp"
cp Sources/PaperCodexApp/Resources/AppIcon.icns "$resources_path/AppIcon.icns"
if compgen -G "Sources/PaperCodexApp/Resources/*.lproj" > /dev/null; then
  cp -R Sources/PaperCodexApp/Resources/*.lproj "$resources_path/"
fi

cat > "$contents_path/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>PaperCodexApp</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleName</key>
  <string>Paper Codex</string>
  <key>CFBundleDisplayName</key>
  <string>Paper Codex</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
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

codesign_args=(
  --force
  --deep
  --sign "$codesign_identity"
  --identifier "$bundle_identifier"
)

if [[ "$codesign_identity" == "-" ]]; then
  codesign_args+=(--requirements "=designated => identifier \"$bundle_identifier\"")
fi

codesign "${codesign_args[@]}" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "$app_path"
