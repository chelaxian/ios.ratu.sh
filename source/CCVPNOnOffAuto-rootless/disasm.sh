#!/bin/bash
# Diagnose why ne_session_establish_ipc / set_event_handler crash the daemon.
LIB=/usr/lib/system/libsystem_networkextension.dylib
BIN=/var/jb/usr/bin/ccvpnd

echo "=== daemon entitlements ==="
ldid -e "$BIN" 2>/dev/null || codesign -d --entitlements - "$BIN" 2>&1

echo "=== all ne_session T symbols ==="
nm -gU "$LIB" 2>/dev/null | grep ' T _ne_session_' || otool -Iv "$LIB" 2>/dev/null | grep ne_session_

echo "=== dumping text disasm ==="
otool -tV "$LIB" > /tmp/ne_disasm.txt 2>&1
wc -l /tmp/ne_disasm.txt

for fn in _ne_session_create _ne_session_start _ne_session_stop \
          _ne_session_establish_ipc _ne_session_set_event_handler \
          _ne_session_start_with_options _ne_session_start_on_behalf_of \
          _ne_session_use_as_system_vpn _ne_session_get_status \
          _ne_session_enable_on_demand; do
  echo "================= $fn ================="
  grep -A28 -E "^${fn}:" /tmp/ne_disasm.txt | head -30
done
echo DISASM_DONE
