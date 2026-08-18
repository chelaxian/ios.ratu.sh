#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
echo "=== wait 22s for a watchdog tick (AUTO is on, WG up) ==="
sleep 22
echo "=== tick/auto/lift lines ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'auto tick|auto:|lift|reconnect|broadcast' | head -20
echo "=== full provider proc scan ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'wireguard|extension|tunnel|vpn|nepacket|amnezia|networkextension|NETunnel' | grep -v grep | head -20
echo "=== ALL procs containing net ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'net' | grep -v grep | head -30
echo TICK_DONE
