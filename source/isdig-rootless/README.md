# isdig for Dopamine

`com.ratush.isdig` 1.1.0 is a Python DNS diagnostic CLI for standard
rootless (`iphoneos-arm64`) environments. Its only executable is installed
at `/var/jb/usr/bin/isdig`; it depends on Python 3 and CA certificates.
There is no tweak injection, daemon, native PreferenceBundle, or respring.

The old rootless archive contained `/usr/bin/isdig` and failed to unpack
on Dopamine's read-only root filesystem. Merely changing Architecture did
not relocate the payload. The new builder stages under `/var/jb`, uses a
temporary Linux filesystem to normalize ownership/modes, and does not
reference a workstation-specific source directory or missing postinst.

## Build and test

```sh
python3 test_isdig.py
bash build.sh
dpkg-deb -c packages/com.ratush.isdig_1.1.0_iphoneos-arm64.deb
```

Run from Linux/WSL with `dpkg-deb`, `install`, and Python 3.9 or newer.
The builder works from any source location. `build_wsl.sh` is an alias.
The separate historical RootHide archive is not rebuilt by this source.

## Examples

```sh
isdig --version
isdig example.com +json
isdig @1.1.1.1 example.com +short
isdig @tcp://1.1.1.1 example.com AAAA +short
isdig @tls://1.1.1.1 example.com +short
isdig @https://dns.google/dns-query example.com +json
isdig @127.0.0.1:5353 example.com
isdig @tcp://[::1]:5353 example.com
isdig @1.1.1.1 -x 2001:4860:4860::8888 +short
isdig --timeout 3 @1.1.1.1 gmail.com MX +short
```

Default nameserver selection reads Procursus `/var/jb/etc/resolv.conf`
and then `/etc/resolv.conf`. It does **not** inspect iOS scoped DNS, VPN
resolver policy, or app-specific resolver state. Use an explicit server to
compare paths. There is no silent fallback to a hardcoded public resolver.
TLS certificate verification is enabled for DoT and DoH.

Version 1.1.0 fixes IPv6 reverse nibbles, SRV decoding, random transaction
IDs, response ID validation, malformed/compression-loop handling, TCP
retry on truncated UDP, and custom ports. It accepts positional record
types and rejects invalid types/options. DNS errors such as NXDOMAIN are
reported in the response and preserve dig-style exit 0; network/parser
failures exit 1 and argument errors exit 2.

`+trace` was advertised but ignored in 1.0.0. Iterative tracing remains
unsupported; 1.1.0 explicitly rejects it. IPv6 PTR queries are supported;
IPv6 transport additionally requires working IPv6 connectivity.

## Live validation, 2026-10-19

Verified on iPhone15,3 / iOS 17.0 (21A329) / Dopamine 3.0.10:

- Rootless package inspection and installation; all files beneath `/var/jb`.
- All 12 offline regression tests on Windows and on the iPhone, including
  real loopback UDP/TCP exchanges and truncated UDP to TCP retry.
- Public UDP, TCP, DoT, DoH; A/AAAA/MX/TXT/NS/SOA; IPv4/IPv6 PTR; NXDOMAIN.
- Default resolv.conf server, JSON output, and short output.

Rollback for a first installation: remove **only** `com.ratush.isdig`
using Sileo or privileged `apt-get remove com.ratush.isdig`. Do not use
autoremove as part of rollback. The old archive is not a working Dopamine
rollback because it targets the sealed filesystem.
