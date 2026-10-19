#!/usr/bin/env bash
# Pure Python CLI: no injected Mach-O components, no arm64e builder required.
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/pkg/DEBIAN" "$work/pkg/var/jb/usr/bin" "$src/packages"
install -m 0644 "$src/layout/DEBIAN/control" "$work/pkg/DEBIAN/control"
install -m 0755 "$src/layout/usr/bin/isdig" "$work/pkg/var/jb/usr/bin/isdig"
version=$(sed -n 's/^Version: //p' "$work/pkg/DEBIAN/control")
pkg="$src/packages/com.ratush.isdig_${version}_iphoneos-arm64.deb"
dpkg-deb -Zgzip --root-owner-group -b "$work/pkg" "$pkg"
dpkg-deb -f "$pkg" Package Version Architecture Depends
dpkg-deb -c "$pkg"
