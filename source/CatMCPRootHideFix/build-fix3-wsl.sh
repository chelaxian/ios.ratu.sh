#!/usr/bin/env bash
set -euo pipefail

root=/home/chelaxian/catmcp-fixed
output=/mnt/c/Users/r_ratush/Desktop/CatMCP-backup-work/com.catmcp.daemon_1.0.3-roothidefix3_iphoneos-arm64e.deb

rm -rf "$root"
mkdir -p "$root"
cp -a /mnt/c/Users/r_ratush/Desktop/CatMCP-backup-work/buildroot/. "$root/"

find "$root" -type d -exec chmod 0755 {} +
chmod 0755 \
  "$root/DEBIAN/postinst" \
  "$root/DEBIAN/prerm" \
  "$root/DEBIAN/postrm" \
  "$root/usr/libexec/catmcp-watchdog" \
  "$root/usr/bin/catmcp" \
  "$root/Library/MobileSubstrate/DynamicLibraries/catmcp.dylib" \
  "$root/Library/PreferenceBundles/catmcp.bundle/catmcp"
chmod 0644 \
  "$root/DEBIAN/control" \
  "$root/usr/lib/catmcp-rootfix.dylib" \
  "$root/Library/LaunchDaemons/com.catmcp.watchdog.plist"

size="$(du -sk "$root" | cut -f1)"
sed -i "s/^Installed-Size:.*/Installed-Size: $size/" "$root/DEBIAN/control"

cd "$root"
find . -path ./DEBIAN -prune -o -type f -print0 |
  sort -z |
  while IFS= read -r -d '' file; do
    md5sum "$file" | sed 's#  ./#  #'
  done > DEBIAN/md5sums

dpkg-deb --root-owner-group -Zgzip -b . "$output"
dpkg-deb -I "$output"
dpkg-deb -c "$output" | grep -E 'catmcp-rootfix|catmcp-watchdog|usr/bin/catmcp'
