#!/bin/bash
sudo -S dpkg -i /tmp/ccvpn.deb < ~/sudoi.pass
PID=$(sudo -S launchctl list < ~/sudoi.pass | grep ccvpnd | awk '{print $1}')
echo "oldpid=$PID"
sudo -S kill -9 "$PID" < ~/sudoi.pass 2>/dev/null
sleep 3
echo "--- new proc ---"
sudo -S launchctl list < ~/sudoi.pass | grep ccvpnd
echo "--- launchd err ---"
sudo -S tail -n 25 /var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err < ~/sudoi.pass 2>/dev/null
echo "RESTART_DONE"
