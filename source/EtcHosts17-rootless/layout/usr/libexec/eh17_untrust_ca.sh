#!/bin/sh
# EtcHosts17: restore the original TrustStore (undo eh17_trust_ca.sh).
# Used on uninstall so we never leave our CA trusted for SSL.
set -e
TS=/rootfs/private/var/protected/trustd/private/TrustStore.sqlite3
BACKUP=/var/mobile/Library/EtcHosts17/TrustStore.sqlite3.bak

if [ ! -f "$BACKUP" ]; then
    echo "eh17_untrust: no backup at $BACKUP; nothing to restore" >&2
    exit 0
fi
cp "$BACKUP" "$TS"
killall trustd 2>/dev/null || true
echo "eh17_untrust: TrustStore restored"
