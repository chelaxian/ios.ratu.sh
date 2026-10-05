# Dopamine migration status

Published rootless packages are built on macOS/Xcode and pass the PTRAUTH arm64e gate where they load in platform processes. None has been installed on the iPhone during this publication pass.

## Published

- `com.ratush.iggridfeed` `0.5.2`
- `com.ratush.appabetical` `1.0.16`
- `com.ratush.ccgapcloser` `0.4.7`
- `com.ratush.jetsamfix` `1.0.1`
- `com.ratush.safeguard` `1.2.1`
- `com.ratush.crontweak` `1.2.0`
- `com.ratush.catmcpcc` `1.0.0+ratu10`
- `com.ratush.ccopenssh` `1.0.10`
- `com.ratush.ccvpnonoffauto` `1.0.1`
- `com.ratush.cchppe` `1.0.1`
- `com.ratush.etchosts17` `0.8.1`
- `com.ratush.isdig` `1.0.0`

## Existing rootless packages to audit, not replace

- `com.ratush.hppe` (user-maintained current rootless build)
- `com.ratush.tgproxyrotation`
- `ru.danpashin.twackup` and `ru.danpashin.twackup-gui`
- `com.ratush.catmcp-rootless-fix`

## Blocked by missing source or rootless base

- `com.ratush.vpnappbridge`: depends on `com.snail.autovpn.global`; only a RootHide arm64e binary is present and no source is available.
- `com.snail.autovpn.global`, `com.choco.tg`, `com.netskao.appdata`, `com.noisyflake.albummanager`, and `xyz.cypwn.cr4shed`: no owned buildable source in this repository.
- `com.ratush.offloader*fix`: historical diagnostic helpers, superseded by the independent implementation below.

## 2026-10-05 — Offloader replacement

`com.level3tjg.offloader` `1.0.0` is rebuilt from the new owned source in [`Offloader-rootless`](Offloader-rootless). Its macOS/Xcode build, 252 host assertions, 103 UIKit Simulator assertions, rootless layout, PTRAUTH ABI and signed code page hashes pass. The old closed-source base is not included. Physical iOS 17.0/Dopamine behavior is **NOT TESTED** because the owner forbids phone access and will install/check it independently. See [validation](Offloader-rootless/VALIDATION-20261005.md) for the per-function matrix and artifact hash.

## Remaining owned-source migrations

EtcHosts17 and CCHPPE are already published as Dopamine rootless builds. Remaining work is audit/follow-up for the packages listed in [`DOPAMINE-ROOTLESS-AUDIT.md`](DOPAMINE-ROOTLESS-AUDIT.md), plus any future owned-source integrations whose runtime dependencies are verified.
