#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err

echo "=== utun now (WG should be up) ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== FULL process scan for tunnel provider ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -ivE '^.{0,40}(grep|kernel_task|launchd|amfid|trustd)' | grep -iE 'wireguard|extension|tunnel|vpn|network|nepacket|amnezia' | head -30
echo
echo "=== LONGPRESS -> AUTO ==="
python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('long rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.long'))"
echo "=== wait 3s, capture AUTO-on log ==="
sleep 3
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | tail -8
echo "=== wait 22s through a watchdog tick ==="
sleep 22
echo "=== log after watchdog tick ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | tail -12
echo AUTOTEST1_DONE
