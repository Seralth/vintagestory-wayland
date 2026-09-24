#!/usr/bin/env bash
# Installs vintagestory-wayland for the current user. See README.md.
#
#   ./install.sh                  take over the existing Vintage Story launcher entry
#   ./install.sh '<command>'      use <command> to start the game instead of the entry's own
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data/applications"
hook_dir="$data/vintagestory-wayland"
wrapper="$HOME/.local/bin/vintagestory-wayland"
marker='X-VintageStoryWayland'

dll="$here/VintageStoryWaylandHook.dll"
[ -f "$dll" ] || dll="$here/src/bin/Release/net10.0/VintageStoryWaylandHook.dll"
if [ ! -f "$dll" ]; then
  echo "VintageStoryWaylandHook.dll not found. Use a release archive, or build it first (see README.md)." >&2
  exit 1
fi

# The launcher entry to take over: one we installed earlier, else the user's own, else the system's.
find_entry() {
  local dir f
  for dir in "$apps" /usr/local/share/applications /usr/share/applications; do
    for f in "$dir"/*.desktop; do
      [ -f "$f" ] || continue
      if grep -q "^$marker=true" "$f" || grep -qiE '^Name=Vintage ?Story$' "$f"; then
        echo "$f"
        return
      fi
    done
  done
}

entry="$(find_entry || true)"
original=''
if [ -n "$entry" ]; then
  original="$(grep -m1 "^$marker-OriginalExec=" "$entry" | cut -d= -f2- || true)"
  [ -n "$original" ] || original="$(grep -m1 '^Exec=' "$entry" | cut -d= -f2- || true)"
fi

game="${1:-$original}"
if [ -z "$game" ]; then
  for candidate in /usr/bin/vintagestory "$data/vintagestory/run.sh" "$data/vintagestory/Vintagestory" /opt/vintagestory/run.sh; do
    if [ -x "$candidate" ]; then
      game="$candidate"
      break
    fi
  done
fi
# Drop desktop-entry field codes (%U, %f, ...); the wrapper passes its own arguments on.
game="$(printf '%s' "$game" | sed -E 's/[[:space:]]*%[fFuUdDnNickvm]//g')"

if [ -z "$game" ]; then
  echo "Could not find how Vintage Story is started. Pass the command: ./install.sh '/path/to/vintagestory'" >&2
  exit 1
fi
case "$game" in
  *flatpak*)
    echo "The Flatpak build is not supported: a startup hook cannot be passed into its sandbox." >&2
    exit 1
    ;;
  *vintagestory-wayland*)
    echo "The launcher already points at a vintagestory-wayland wrapper. Run ./uninstall.sh first, or pass the game command." >&2
    exit 1
    ;;
esac

install -Dm644 "$dll" "$hook_dir/VintageStoryWaylandHook.dll"
mkdir -p "$(dirname "$wrapper")"
cat > "$wrapper" <<WRAPPER
#!/bin/sh
# Starts Vintage Story with the vintagestory-wayland startup hook. Written by install.sh.
export DOTNET_STARTUP_HOOKS="$hook_dir/VintageStoryWaylandHook.dll\${DOTNET_STARTUP_HOOKS:+:\$DOTNET_STARTUP_HOOKS}"
exec $game "\$@"
WRAPPER
chmod 755 "$wrapper"

# Point the launcher entry at the wrapper. The previous command is kept in the entry itself so
# uninstall.sh can put it back; a system entry is overridden by a copy in the user's own folder.
mkdir -p "$apps"
if [ -z "$entry" ]; then
  target="$apps/vintagestory-wayland.desktop"
  cat > "$target" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Vintage Story
Icon=vintagestory
Categories=Game;
Terminal=false
StartupWMClass=Vintagestory
Exec=$wrapper
$marker=true
$marker-Created=true
DESKTOP
else
  target="$apps/$(basename "$entry")"
  copied=''
  if [ "$(dirname "$entry")" != "$apps" ] || grep -q "^$marker-Created=true" "$entry"; then
    copied="$marker-Created=true"
  fi
  codes="$(printf '%s' "$original" | grep -oE '%[fFuUdDnNickvm]' | tr '\n' ' ' | sed 's/ $//' || true)"
  tmp="$(mktemp)"
  awk -v exec="$wrapper${codes:+ $codes}" -v orig="$original" -v m="$marker" -v copied="$copied" '
    index($0, m) == 1 { next }
    /^Exec=/ && !done {
      print "Exec=" exec; print m "=true"; print m "-OriginalExec=" orig
      if (copied != "") print copied
      done = 1; next
    }
    { print }' "$entry" > "$tmp"
  mv "$tmp" "$target"
  chmod 644 "$target"
fi

command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" >/dev/null 2>&1 || true

echo "Installed. Launcher entry: $target"
echo "Game command: $game"
echo "Start Vintage Story from your launcher; each start adds a line to $hook_dir/hook.log."
