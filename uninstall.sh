#!/usr/bin/env bash
# Removes vintagestory-wayland and puts the launcher entry back the way it was.
set -euo pipefail

data="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data/applications"
marker='X-VintageStoryWayland'

for f in "$apps"/*.desktop; do
  [ -f "$f" ] || continue
  grep -q "^$marker=true" "$f" || continue
  if grep -q "^$marker-Created=true" "$f"; then
    rm -f "$f"
    echo "Removed launcher entry $f"
  else
    original="$(grep -m1 "^$marker-OriginalExec=" "$f" | cut -d= -f2-)"
    tmp="$(mktemp)"
    awk -v orig="$original" -v m="$marker" '
      index($0, m) == 1 { next }
      /^Exec=/ && !done { print "Exec=" orig; done = 1; next }
      { print }' "$f" > "$tmp"
    mv "$tmp" "$f"
    chmod 644 "$f"
    echo "Restored launcher entry $f (Exec=$original)"
  fi
done

rm -f "$HOME/.local/bin/vintagestory-wayland"
rm -rf "$data/vintagestory-wayland"

command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" >/dev/null 2>&1 || true
echo "Uninstalled."
