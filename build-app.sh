#!/usr/bin/env bash
# Builds ClipShelf.app (Apple Silicon) into ./build.
#   ./build-app.sh            release build
#   ./build-app.sh --install  also copy it to /Applications
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release --arch arm64

app="build/ClipShelf.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClipShelf" "$app/Contents/MacOS/ClipShelf"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signature so macOS will run it locally. macOS ties the Accessibility
# permission to the signature, so after a rebuild you may need to re-enable
# ClipShelf in System Settings > Privacy & Security > Accessibility.
codesign --force --sign - "$app"

echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/ClipShelf.app
  cp -R "$app" /Applications/
  echo "Installed /Applications/ClipShelf.app"
fi
