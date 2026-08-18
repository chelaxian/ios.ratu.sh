#!/bin/bash
# Tap then wait long enough for async start + provider launch, check all.
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err

echo "=== utun before ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== provider procs before ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'quantumult|NEPacketTunnel|nesessionmanager|networkextension|wireguard|amnezia|tunnel' | grep -v grep | head

echo "=== TAP ==="
python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('tap rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.tap'))"

echo "=== waiting 25s ==="
sleep 25

echo "=== utun after ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== utun mtus ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -E 'utun[0-9]:'
echo "=== provider procs after ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'quantumult|NEPacketTunnel|nesessionmanager|networkextension|wireguard|amnezia|tunnel' | grep -v grep | head
echo "=== daemon log tail ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | tail -45
echo TAPWAIT_DONE
