#!/bin/bash
cd /home/dev/build/ccvpn-ono-auto
D=packages/com.ratush.ccvpnonoffauto_1.0.0_iphoneos-arm64e.deb
echo "=== deb data.tar ==="
dpkg-deb -c "$D" | grep -E 'ccvpnd|CCVPNOnOffAuto|LaunchDaemons'
rm -rf /tmp/insp
mkdir -p /tmp/insp
dpkg-deb -x "$D" /tmp/insp
echo "--- daemon arches ---"
file /tmp/insp/usr/bin/ccvpnd
echo "--- daemon entitlements ---"
/home/dev/theos/toolchain/linux/iphone/bin/ldid -e /tmp/insp/usr/bin/ccvpnd
echo "--- bundle arches ---"
file /tmp/insp/Library/ControlCenter/Bundles/CCVPNOnOffAuto.bundle/CCVPNOnOffAuto
echo "--- launchd plist ---"
cat /tmp/insp/Library/LaunchDaemons/com.ratush.ccvpnd.plist
echo "INSPECT_DONE"
