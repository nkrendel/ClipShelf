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

# macOS ties the Accessibility permission to the app's signature. An ad-hoc
# signature changes with every build, so the permission would stop working
# after each rebuild. A real certificate keeps it stable: use the first
# "Apple Development" identity (or $CLIPSHELF_SIGN_IDENTITY), else ad-hoc.
identity="${CLIPSHELF_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app"
  echo "Signed with $identity"
else
  codesign --force --sign - "$app"
  echo "Ad-hoc signed: re-enable Accessibility after each rebuild"
fi

echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/ClipShelf.app
  cp -R "$app" /Applications/
  echo "Installed /Applications/ClipShelf.app"
fi
