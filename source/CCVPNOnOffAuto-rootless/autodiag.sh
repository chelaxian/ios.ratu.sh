#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('long rc=', l.notify_post(b'com.ratush.ccvpnonoffauto.cmd.long'))"
sleep 3
echo "--- LONGPRESS/AUTO/tick lines ---"
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'longpress|AUTO|watchdog|tick|cmd\.|lift' | tail -25
echo "--- whole log last 30 ---"
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | tail -30
echo AUTODIAG_DONE
