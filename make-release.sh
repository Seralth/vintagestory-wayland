#!/usr/bin/env bash
# Builds the hook and writes dist/vintagestory-wayland-<version>.tar.gz.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/VintageStoryWaylandHook.csproj)"
dotnet build src -c Release -nologo -v q
stage="dist/vintagestory-wayland-$version"
rm -rf "$stage"
mkdir -p "$stage"
cp src/bin/Release/net10.0/VintageStoryWaylandHook.dll install.sh uninstall.sh README.md LICENSE "$stage/"
tar -C dist -czf "dist/vintagestory-wayland-$version.tar.gz" "vintagestory-wayland-$version"
rm -rf "$stage"
echo "dist/vintagestory-wayland-$version.tar.gz"
