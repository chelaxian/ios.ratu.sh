#!/bin/bash
# Build com.ratush.isdig .deb in WSL-native fs (avoids /mnt/c 0777 perms).
set -e
SRC="/mnt/c/Users/chelaxian/Documents/iPhone 14 Pro Max iOS 17.0 semi-jailbreak Roothide Bootstrap 2.2/isdig-pkg"
WORK=/tmp/isdig-build
rm -rf "$WORK"
mkdir -p "$WORK"
cp -r "$SRC/layout" "$WORK/"
find "$WORK" -type d -exec chmod 0755 {} +
find "$WORK" -type f -exec chmod 0644 {} +
chmod 0755 "$WORK/layout/usr/bin/isdig" "$WORK/layout/DEBIAN/postinst"
mkdir -p "$SRC/packages"
dpkg-deb -Zgzip --root-owner-group -b "$WORK/layout" "$SRC/packages/com.ratush.isdig_1.0.0_iphoneos-arm64e.deb"
echo "BUILT"
dpkg-deb --info "$SRC/packages/com.ratush.isdig_1.0.0_iphoneos-arm64e.deb" | grep -E 'Package|Version|Architecture'
