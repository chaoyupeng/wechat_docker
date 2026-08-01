#!/usr/bin/env bash
# Build "Start WeChat.app" / "Stop WeChat.app" — double-clickable wrappers
# around ./wechat. Re-run this if you move the repo or edit the launcher.
#
#   ./build-apps.sh             build them here in the repo
#   ./build-apps.sh --install   build into /Applications instead, so they show
#                               up in Spotlight and Launchpad
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd)"

DEST="$REPO"
if [ "${1:-}" = "--install" ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || { echo "/Applications is not writable by you." >&2; exit 1; }
fi

build() {
  # Separate statements: bash expands every word of a `local` before assigning
  # any of them, so "$name" would still be unset if declared on one line.
  local name="$1"
  local action="$2"
  local icon="$3"
  local app="$DEST/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>local.wechatsandbox.$action</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

  cat > "$app/Contents/MacOS/launcher" <<LAUNCHER
#!/bin/bash
# Homebrew is not on PATH for GUI-launched apps; set it explicitly.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

# Prefer the repo this .app currently sits in, so moving the whole folder works.
REPO="\$(cd "\$(dirname "\$0")/../../.." && pwd)"
[ -x "\$REPO/wechat" ] || REPO="$REPO"

LOG=/tmp/wechat-sandbox.log
notify() { osascript -e "display notification \"\$1\" with title \"WeChat Sandbox\"" >/dev/null 2>&1; }

cd "\$REPO" || { notify "Cannot find the repo"; exit 1; }

case "$action" in
  start) notify "Starting… the VM takes about 20s on a cold boot." ;;
  stop)  notify "Shutting down…" ;;
esac

if ./wechat $action >"\$LOG" 2>&1; then
  case "$action" in
    start) notify "WeChat is ready." ;;
    stop)  notify "Stopped." ;;
  esac
else
  notify "Failed — opening the log."
  open -a TextEdit "\$LOG"
fi
LAUNCHER

  chmod +x "$app/Contents/MacOS/launcher"
  cp "$icon" "$app/Contents/Resources/icon.icns"
  # Nudge Finder/LaunchServices to pick up the new bundle + icon.
  touch "$app"
  echo "built $app"
}

build "Start WeChat" start "$REPO/icons/start.icns"
build "Stop WeChat"  stop  "$REPO/icons/stop.icns"
