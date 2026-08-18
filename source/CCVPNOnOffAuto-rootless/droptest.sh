#!/bin/bash
PASS=~/sudoi.pass
ERR=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
echo "=== utun before (WG up) ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
sudo -S sh -c ": > $ERR" < $PASS 2>/dev/null
echo "=== KILL WG provider (simulate drop) ==="
sudo -S killall -9 WireGuardNetworkExtension < $PASS 2>&1 | head -2
sleep 4
echo "=== utun after kill (should drop) ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== anyActive right after kill? ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'auto tick|anyActive|reconnect|startVPN' | tail -8
echo "=== wait 25s for watchdog reconnect ==="
sleep 25
echo "=== utun after watchdog (should recover) ==="
sudo -S ifconfig < $PASS 2>/dev/null | grep -cE 'utun[0-9]:'
echo "=== WG provider respawned? ==="
sudo -S ps -axo pid,comm < $PASS 2>/dev/null | grep -iE 'wireguard' | grep -v grep | head
echo "=== reconnect log ==="
sudo -S cat $ERR < $PASS 2>/dev/null | sed 's/^.*+0000 //' | grep -iE 'auto tick|auto:|reconnect|startVPN|conn wait|anyActive' | tail -15
echo DROP_DONE
