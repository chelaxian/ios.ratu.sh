#!/bin/bash
set -e
cd /home/chelaxian/crontweak-build-src
DEB=./packages/com.ratush.crontweak_1.2.0_iphoneos-arm64e.deb
echo "=== before ==="
dpkg-deb --info "$DEB" | head -20
rm -rf /home/chelaxian/crontweak-repack
mkdir -p /home/chelaxian/crontweak-repack
dpkg-deb -R "$DEB" /home/chelaxian/crontweak-repack
cp postinst prerm /home/chelaxian/crontweak-repack/DEBIAN/
chmod 0755 /home/chelaxian/crontweak-repack/DEBIAN/postinst /home/chelaxian/crontweak-repack/DEBIAN/prerm
cd /home/chelaxian/crontweak-repack
rm -f DEBIAN/md5sums
find . -path ./DEBIAN -prune -o -type f -print -exec md5sum {} \; | grep -v "^\./DEBIAN" | sed "s#^\./##" > DEBIAN/md5sums
cd /home/chelaxian/crontweak-build-src
dpkg-deb -Zgzip --root-owner-group -b /home/chelaxian/crontweak-repack "$DEB"
echo "=== after ==="
dpkg-deb --info "$DEB"
dpkg-deb -c "$DEB" | grep -E "postinst|prerm|DEBIAN"
