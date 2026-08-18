#!/bin/bash
# deploy fresh daemon, tap, verify ne_session connects the VPN
set +e
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
TMPLOG=/var/tmp/ccvpnd.log
PLIST=/var/jb/Library/LaunchDaemons/com.ratush.ccvpnd.plist

echo "=== dpkg -i ==="
sudo -S dpkg -i /tmp/ccvpn.deb < $PASS 2>&1 | tail -3

echo "=== truncate logs ==="
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
sudo -S sh -c ": > $TMPLOG" < $PASS 2>/dev/null

echo "=== reload launchd ==="
sudo -S launchctl bootout system $PLIST < $PASS 2>/dev/null
sleep 1
PID=$(sudo -S launchctl list < $PASS | grep ccvpnd | awk '{print $1}')
[ -n "$PID" ] && sudo -S kill -9 "$PID" < $PASS 2>/dev/null
sudo -S launchctl bootstrap system $PLIST < $PASS 2>/dev/null
sudo -S launchctl enable system/com.ratush.ccvpnd < $PASS 2>/dev/null
sleep 5

echo "=== launchctl list ==="
sudo -S launchctl list < $PASS | grep ccvpnd

echo "=== startup log ==="
sudo -S tail -n 24 $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //'

echo "=== utun before ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'

echo "=== TAP ==="
python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('tap rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.tap'))"
sleep 9

echo "=== utun after ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== utun mtus ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -E 'utun[0-9]:'

echo "=== provider / NE procs ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'quantumult|NEPacketTunnel|nesessionmanager|networkextension' | grep -v grep | head

echo "=== daemon log (tmp) ==="
sudo -S tail -n 40 $TMPLOG < $PASS 2>/dev/null | sed 's/^.*+0000 //'

echo "=== daemon log (launchd err) ==="
sudo -S tail -n 40 $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //'

echo "TEST_DONE"
