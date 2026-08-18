#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
echo "=== daemon alive? ==="
sudo -S launchctl list < $PASS 2>/dev/null | grep ccvpnd
echo "=== keepalive in plist? ==="
sudo -S plutil -p /var/jb/Library/LaunchDaemons/com.ratush.ccvpnd.plist < $PASS 2>/dev/null | grep -iE 'KeepAlive|RunAtLoad|Label|Program'
echo "=== truncate log, post all 3 ==="
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
for n in tap query longpress; do
  python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('$n rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.$n'))"
  sleep 2
done
echo "=== full log after all 3 ==="
sleep 2
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'cmd\.|OnCmd|longpress|AUTO|tick|loaded|pick|startVPN|stopVPN|conn wait|any=|completion' | head -60
echo QUICK_DONE
