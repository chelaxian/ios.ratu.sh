#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
PLIST=/var/jb/Library/LaunchDaemons/com.ratush.ccvpnd.plist
echo "=== dpkg -i ==="
sudo -S dpkg -i /tmp/ccvpn.deb < $PASS 2>&1 | tail -2
echo "=== restart daemon ==="
sudo -S launchctl bootout system $PLIST < $PASS 2>/dev/null
sleep 1
PID=$(sudo -S launchctl list < $PASS | grep ccvpnd | awk '{print $1}')
[ -n "$PID" ] && sudo -S kill -9 "$PID" < $PASS 2>/dev/null
sudo -S launchctl bootstrap system $PLIST < $PASS 2>/dev/null
sleep 3
sudo -S launchctl list < $PASS | grep ccvpnd
echo "=== clear CC tile log + daemon log ==="
defaults delete com.ratush.ccvpnonoffauto log 2>/dev/null
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
echo "=== bundle files ==="
sudo -S ls /var/jb/Library/ControlCenter/Bundles/CCVPNOnOffAuto.bundle/ < $PASS 2>/dev/null
echo "=== sbreload (respring) ==="
sudo -S sbreload < $PASS 2>&1 | tail -1
echo DEPLOY_DONE
