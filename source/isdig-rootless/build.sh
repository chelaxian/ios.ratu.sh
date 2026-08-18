#!/bin/bash
# Build com.ratush.isdig .deb (pure-data package, no compilation).
set -e
cd "$(dirname "$0")"
# Normalize permissions (WSL /mnt/c copies make everything 0777).
find layout -type d -exec chmod 0755 {} +
find layout -type f -exec chmod 0644 {} +
chmod 0755 layout/usr/bin/isdig layout/DEBIAN/postinst
mkdir -p packages
pkg="packages/com.ratush.isdig_1.0.0_iphoneos-arm64e.deb"
dpkg-deb -Zgzip --root-owner-group -b layout "$pkg"
echo "Built $pkg"
dpkg-deb --info "$pkg" | grep -E 'Package|Version|Architecture'
