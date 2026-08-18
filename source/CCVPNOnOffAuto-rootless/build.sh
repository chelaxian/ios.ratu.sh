#!/bin/bash
# Build CCVPN-ON-OFF-AUTO. Run from host via:
#   wsl -d Ubuntu-24.04 -u dev -- bash -c "sed -i 's/\x0D//g' /mnt/c/Users/chelaxian/iosjail-work/ccvpn-ono-auto/build.sh; bash /mnt/c/Users/chelaxian/iosjail-work/ccvpn-ono-auto/build.sh"
set -e
export THEOS=/home/dev/theos
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"

SRC=/mnt/c/Users/chelaxian/iosjail-work/ccvpn-ono-auto
DST=/home/dev/build/ccvpn-ono-auto

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/
cd "$DST"

echo "=== strip CRLF ==="
find . -type f \( -name '*.m' -o -name '*.h' -o -name 'Makefile' -o -name 'control' -o -name '*.plist' -o -name '*.sh' \) -exec sed -i 's/\x0D//g' {} +

echo "=== make clean package ==="
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

echo "=== packages ==="
ls -la packages/

echo "=== copy deb back to project ==="
cp -f packages/*.deb "$SRC/" 2>/dev/null || true
ls -la "$SRC"/*.deb 2>/dev/null

echo "BUILD_DONE"
