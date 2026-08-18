#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
echo "=== all network-ish procs ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'extension|wireguard|vpn|tunnel|network|nepacket|amnezia|quantum|xray' | grep -v grep | head -20
echo "=== routes via utun4 ==="
sudo -S netstat -rn < $PASS 2>/dev/null | grep -E 'utun4|default' | head -10
echo "=== utun4 detail ==="
sudo -S ifconfig utun4 < $PASS 2>/dev/null
echo "=== CMD_QUERY (daemon recomputes anyActive) ==="
python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('q rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.query'))"
sleep 3
echo "=== daemon log tail (last 15) ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | tail -15
echo DIAG_DONE
