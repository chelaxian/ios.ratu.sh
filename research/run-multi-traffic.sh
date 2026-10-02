#!/bin/sh
set -eu
daemon=$(ps -A -o pid,comm | awk '$2 == "/var/jb/usr/libexec/appsplitvpnd" {print $1}')
test -n "$daemon"
output=/var/mobile/asv040-probe-output.txt
child=
captures=
cleanup() {
 trap - EXIT HUP INT TERM
 if test -n "$child"; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
 for pid in $captures; do kill -INT "$pid" 2>/dev/null || true; done
 /var/mobile/asv-multi-session-probe restore || true
 kill -CONT "$daemon"
 /var/mobile/asv-multi-session-probe split-restore || true
}
trap cleanup EXIT HUP INT TERM
/var/mobile/asv-multi-session-probe split-off
kill -STOP "$daemon"
/var/mobile/asv-multi-session-probe "$@" >"$output" 2>&1 &
child=$!
ready=0
for n in $(seq 1 30); do
 if grep -Eq 'POLICIES_APPLIED=1 READY|BASELINE_READY' "$output"; then ready=1; break; fi
 kill -0 "$child" 2>/dev/null || break
 sleep 1
done
if test "$ready" = 1; then
 if test "${ASV_PROBE_NATIVE_RULES:-0}" = 1; then
  echo NATIVE_APP_TEST_READY
  for interface in $(awk '/^NATIVE_APP_ROUTE/ {print $3}' "$output"); do
   /var/jb/usr/bin/tcpdump -n -t -i "$interface" -c 100 -s 40 -xx >"/var/mobile/asv040-$interface.txt" 2>&1 &
   captures="$captures $!"
  done
  if test "${ASV_RESTART_APPS:-0}" = 1; then
   for pid in $(ps -A -o pid,comm | awk '$2 ~ /\/(WhatIsMyIP|myip-ios).app\/(WhatIsMyIP|myip-ios)$/ {print $1}'); do kill -TERM "$pid" 2>/dev/null || true; done
   sleep 2
   /var/jb/usr/bin/uiopen --bundleid mobi.secured.whatsmyip
   sleep 4
   /var/jb/usr/bin/uiopen --bundleid com.monvpn.myip
  fi
  if test "${ASV_WG_STATS:-0}" = 1; then /var/mobile/asv-multi-session-probe-next stats 02414AFC-4D04-468C-A61C-42EFF2445475 || true; fi
 else
 echo CURL_NUMERIC
 if command -v netstat >/dev/null; then netstat -rn -f inet | grep -E 'default|utun' || true; fi
 /var/jb/usr/bin/curl -4 -sS --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace | grep -E '^(ip|loc)=' || true
 echo WGET_NUMERIC
 /var/jb/usr/bin/wget -4 -qO- -T 10 https://1.1.1.1/cdn-cgi/trace | grep -E '^(ip|loc)=' || true
 fi
fi
wait "$child" || true
child=
for pid in $captures; do kill -INT "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
captures=
if test "${ASV_PROBE_NATIVE_RULES:-0}" = 1; then
 for interface in $(awk '/^NATIVE_APP_ROUTE/ {print $3}' "$output"); do
  echo "CAPTURE_INTERFACE=$interface"
  grep -E '^listening|packets captured|packets received|packets dropped' "/var/mobile/asv040-$interface.txt" || true
 done
fi
cat "$output"
