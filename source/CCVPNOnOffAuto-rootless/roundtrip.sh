#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
post() {
  python3 -c "import ctypes; l=ctypes.CDLL('/usr/lib/libSystem.dylib'); l.notify_post.argtypes=[ctypes.c_char_p]; print('$1 rc=', l.notify_post(b'$2'))"
}
echo "=== CMD_LONG #1 (enable AUTO) ==="
post long1 com.ratush.ccvpnonoffauto.cmd.longpress
sleep 4
echo "=== daemon AUTO-on log ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'cmd.longpress|AUTO on|watchdog started|startVPN|conn wait' | tail -8
echo "=== CMD_LONG #2 (disable AUTO) ==="
post long2 com.ratush.ccvpnonoffauto.cmd.longpress
sleep 2
echo "=== daemon AUTO-off log ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'AUTO off|cmd.longpress' | tail -4
echo ROUNDTRIP_DONE
