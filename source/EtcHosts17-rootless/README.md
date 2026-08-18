# EtcHosts17

Editable `/etc/hosts`-style DNS overrides for RootHide Bootstrap iOS 17. The
sealed system volume makes the real `/etc/hosts` unwritable forever, and
mDNSResponder is a non-injectable platform binary, so this tweak runs a small
local resolver daemon and uses the only DNS-override mechanism iOS surfaces and
enforces: a managed-DNS configuration profile.

## What it does

- A Settings bundle (terminal/CRT themed editor) lets you edit hosts entries
  with IPv4/IPv6 addresses, multiple hostnames per line, inline comments, and
  persistent preset profiles.
- A Python daemon (`etchosts17.py`) runs as a LaunchDaemon and serves:
  - UDP/TCP `:53` — a local resolver that answers overridden hosts from your
    map and forwards everything else upstream.
  - DNS-over-TLS `:853` and DNS-over-HTTPS `:8443` — so a managed-DNS profile
    can route specific hosts to it over an encrypted transport.
  - A localhost HTTP `:53580` server that serves a freshly generated
    `.mobileconfig` (bundles the per-device CA + a scoped DNS payload) so the
    Settings "Create profile" button hands you straight into the iOS install
    sheet.
- A scoped managed-DNS profile (`com.apple.dnsSettings.managed` with
  `SupplementalMatchDomains`) routes ONLY the listed hosts to this daemon,
  while everything else keeps using the primary resolver. This is the
  `/etc/hosts` parity: listed hosts win, the rest is untouched.
- A system-resolver redirect helper (`etchosts17resolv`) is kept as a secondary
  mechanism for plain-DNS networks (Wi-Fi/cellular/Ethernet without an active
  managed-DoH resolver) and for full-tunnel VPN DNS.

Two profile modes:
- **Block** — matched hosts answer from the editor map (`0.0.0.0` etc.).
- **Upstream** — matched hosts are forwarded to a real upstream DoT server
  (e.g. `dns.google`); the host is still routed to us so we win over DoH/VPN
  for it, but resolved through the chosen upstream instead of a static address.

## Hard limitations on iOS 17.0 (verified on this device)

These are OS-level ceilings, not bugs in the tweak:

1. **mDNSResponder injection is dead** (platform binary). The `/etc/hosts` file
   is on the APFS sealed system volume and can never be edited.
2. **No `pfctl`, no `scutil`, no `dig`/`nslookup`.** `pkill`/`pgrep` absent.
3. **`State:/Network/Global/DNS` is output-only.** Writing `127.0.0.1` there
   does NOT redirect DNS when a managed-DoH profile (ControlD/NextDNS/AdGuard)
   is the active primary — verified: 0 packets reach the daemon. The
   SCDynamicStore redirect only helps on plain-DNS networks.
4. **A managed-DoH primary makes iOS ignore DoT profiles entirely.** When
   ControlD (DoH) is the active primary, even a GLOBAL DoT profile with public
   IPs gets 0 packets on `:853`. So when a DoH profile is the active primary,
   our scoped resolver must ALSO be DoH to participate in routing.
5. **`saveToPreferences` cannot enable a DNS-settings profile silently** — the
   user must enable it once in Settings ▸ General ▸ VPN & Device Management ▸
   DNS. This is an Apple gate.
6. **A user-installed root CA is NOT trusted for SSL by default.** Apple ships
   it with `sslServer → kSecTrustSettingsResultDeny`. The tweak works around
   this by patching `TrustStore.sqlite3` directly (`eh17_trust_ca.sh`, reverted
   on uninstall), which is the only way short of a manual Settings ▸ General ▸
   About ▸ Certificate Trust Settings toggle.

## Install and use

```sh
dpkg -i packages/com.ratush.etchosts17_0.6.2_iphoneos-arm64e.deb
```

Open Settings ▸ EtcHosts17, edit entries (e.g. `0.0.0.0 ocsp.apple.com`), tap
**Apply**. For the override to win over an active DoH/VPN, also:

1. Turn on **"Use DoH/DoT profile"** and tap **"Create / update DNS profile"**.
2. Safari opens the profile install sheet — Install it.
3. Settings ▸ General ▸ VPN & Device Management ▸ DNS — enable the
   "/etc/hosts (iOS 17.0)" profile (one-time Apple gate).

Pick **DoT** (`:853`, default) or **DoH** (`:8443`) as the profile transport —
DoH is required when a DoH resolver is the active primary (see limitation #4).

Rollback:

```sh
dpkg -r com.ratush.etchosts17
```

The `prerm` restores the system resolver, removes the redirect, and reverts
the CA-trust patch from its backup. State: keys are ephemeral (gone after
reboot), and the scoped profile is removed via the entitled helper.

## Build

```sh
# WSL (Ubuntu), roothide Theos scheme
export THEOS="$HOME/theos"
export THEOS_PACKAGE_SCHEME=roothide
./build.sh
```

The build host must have the roothide Theos mod (`theos/vendor/mod/roothide`).

## References

- LetMeBlock: https://github.com/PoomSmart/LetMeBlock
- PaiBloxx: https://github.com/Paisseon/PaiBloxx
- Apple NEDNSSettings / `com.apple.dnsSettings.managed` profile spec.
