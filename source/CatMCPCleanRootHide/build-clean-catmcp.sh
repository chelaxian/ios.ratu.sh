#!/bin/sh
set -eu

backup=${1:?usage: build-clean-catmcp.sh /path/to/catmcp-installed.tgz [output.deb]}
output=${2:-com.catmcp.daemon_1.0.3_iphoneos-arm64e.deb}
stage=$(mktemp -d)
root="$stage/package"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$root/DEBIAN"
tar -xzf "$backup" -C "$root"

rm -f \
  "$root/Library/MobileSubstrate/DynamicLibraries/catmcp.dylib.roothidepatch" \
  "$root/Library/PreferenceBundles/catmcp.bundle/catmcp.roothidepatch"

cat >"$root/DEBIAN/control" <<'EOF'
Package: com.catmcp.daemon
Name: catmcp
Description: iOS MCP Server
Depends: mobilesubstrate, preferenceloader
Maintainer: 0x530c<0x530c@gmail.com>
Author: 0x530c<0x530c@gmail.com>
Section: Tweaks
Architecture: iphoneos-arm64e
Version: 1.0.3
Installed-Size: 5256
EOF

cat >"$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
chown root:wheel /usr/bin/catmcp
chmod 6755 /usr/bin/catmcp
killall -9 catmcp 2>/dev/null || true
exit 0
EOF

cat >"$root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
killall -9 catmcp 2>/dev/null || true
exit 0
EOF

chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/prerm"
dpkg-deb --root-owner-group --build "$root" "$output"
