#!/usr/bin/env bash
# Usage: rootless-repack.sh <input.deb> <outdir>
# Moves a rootful-layout payload under /var/jb and bumps the version suffix.
set -euo pipefail
in="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$2"; outdir="$(cd "$2" && pwd)"
work="$(mktemp -d)"
dpkg-deb -R "$in" "$work/pkg"
cd "$work/pkg"
if [ -d var/jb ]; then echo "$in already has /var/jb"; exit 1; fi
mkdir -p "$work/stage/var/jb"
find . -mindepth 1 -maxdepth 1 ! -name DEBIAN -exec mv {} "$work/stage/var/jb/" \;
mv "$work/stage/var" ./var
ver="$(sed -n 's/^Version: //p' DEBIAN/control)"
base="${ver%+rootless*}"; base="${base%+device*}"
newver="$base+rootless2"
sed -i.bak "s/^Version: .*/Version: $newver/" DEBIAN/control && rm DEBIAN/control.bak
test -z "$(find . -mindepth 1 -maxdepth 1 ! -name var ! -name DEBIAN)"
test "$(sed -n 's/^Architecture: //p' DEBIAN/control)" = iphoneos-arm64
pkg="$(sed -n 's/^Package: //p' DEBIAN/control)"
out="$outdir/${pkg}_${newver}_iphoneos-arm64.deb"
cd "$work"
dpkg-deb -Zgzip --root-owner-group -b pkg "$out"
if dpkg-deb -c "$out" | awk '{print $6}' | grep -vE '^\./(var/(jb/.*)?)?$'; then echo "payload outside /var/jb"; exit 1; fi
echo "built $out"
