#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

export THEOS="${THEOS:-/root/roothide-theos-codex}"
export THEOS_PACKAGE_SCHEME=roothide

make clean
make package FINALPACKAGE=1

pkg="$(ls -t packages/com.ratush.iggridfeed_*_iphoneos-arm64e.deb | head -1)"
work="$(mktemp -d)"
dpkg-deb -R "$pkg" "$work"
if [ -d layout/DEBIAN ]; then
  cp -f layout/DEBIAN/* "$work/DEBIAN/"
  chmod 0755 "$work/DEBIAN/"*
fi
(cd "$work" && find . -path ./DEBIAN -prune -o -type f -print0 | sort -z | while IFS= read -r -d '' f; do md5sum "$f" | sed 's#  ./#  #'; done > DEBIAN/md5sums)
dpkg-deb -Zgzip --root-owner-group -b "$work" "$pkg"
rm -rf "$work"

ls -la packages/*.deb
