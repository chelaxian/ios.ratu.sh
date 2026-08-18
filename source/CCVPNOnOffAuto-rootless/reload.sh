#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
PLIST=/var/jb/Library/LaunchDaemons/com.ratush.ccvpnd.plist
sudo -S dpkg -i /tmp/ccvpn.deb < $PASS 2>&1 | tail -2
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
sudo -S launchctl bootout system $PLIST < $PASS 2>/dev/null
sleep 1
PID=$(sudo -S launchctl list < $PASS | grep ccvpnd | awk '{print $1}')
[ -n "$PID" ] && sudo -S kill -9 "$PID" < $PASS 2>/dev/null
sudo -S launchctl bootstrap system $PLIST < $PASS 2>/dev/null
sleep 4
sudo -S launchctl list < $PASS | grep ccvpnd
echo RELOAD_DONE
