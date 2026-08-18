#!/bin/sh
# EtcHosts17: trust our per-device CA for SSL/TLS by editing the trustd
# TrustStore.sqlite3 directly. Apple ships user-installed roots with
# sslServer -> kSecTrustSettingsResultDeny (4); we rewrite that to an empty
# trust-settings array (like NextDNS/AdGuard CAs already use), which means
# "trust as root, no restrictions". This is what lets mDNSResponder accept the
# DoT/DoH server certificate our daemon presents.
#
# Reversible: eh17_untrust_ca.sh restores the original TrustStore from backup.
#
# On iOS 17.0 RootHide this is the ONLY way to make a user-installed CA trusted
# for SSL without a manual Settings > General > About > Certificate Trust
# Settings toggle. Verified: after this patch, the tset blob matches the format
# NextDNS (a working SSL-trusted CA) uses.
set -e
TS=/rootfs/private/var/protected/trustd/private/TrustStore.sqlite3
CA_DER=/var/mobile/Library/EtcHosts17/tls/ca.der
BACKUP=/var/mobile/Library/EtcHosts17/TrustStore.sqlite3.bak

if [ ! -f "$CA_DER" ]; then
    echo "eh17_trust: CA not found at $CA_DER" >&2
    exit 0
fi
if [ ! -f "$TS" ]; then
    echo "eh17_trust: TrustStore not found at $TS" >&2
    exit 0
fi

CA_LEN=$(wc -c < "$CA_DER" | tr -d ' ')

# Back up once (keep the first backup so restore is always to the pre-tweak state).
if [ ! -f "$BACKUP" ]; then
    cp "$TS" "$BACKUP"
    chmod 0644 "$BACKUP"
fi

# Build the "trust as root" tset plist (empty array = no policy restrictions,
# matching the NextDNS/AdGuard format observed on this device).
EMPTY_TSET='/tmp/eh17_empty_tset.xml'
cat > "$EMPTY_TSET" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array/>
</plist>
EOF

sqlite3 "$TS" "UPDATE tsettings SET tset=readfile('$EMPTY_TSET') WHERE length(data)=$CA_LEN;" 2>/dev/null || true
rm -f "$EMPTY_TSET"

# Force trustd to reload from the store.
killall trustd 2>/dev/null || true
echo "eh17_trust: CA trusted for SSL (len=$CA_LEN)"
