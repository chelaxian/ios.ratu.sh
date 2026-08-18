#!/bin/bash
F=/var/mobile/Library/Preferences/com.ratush.ccvpnd.launchd.err
echo "--TICKCOUNT--"
grep -c "status tick" "$F"
echo "--LASTSTARTUP--"
grep -n "ccvpnd start\|status sync started\|ne-lib syms" "$F" | tail -3
echo "--LASTTICKS--"
grep "status tick" "$F" | tail -6
echo "--AUTOCOUNT--"
grep -c "auto: VPN down\|AUTO on\|lifted" "$F"
echo "--LAST15--"
tail -15 "$F"
echo DIAGV2_DONE
