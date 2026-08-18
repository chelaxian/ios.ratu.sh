# Dopamine migration status

Published rootless packages are built on macOS/Xcode and pass the PTRAUTH arm64e gate where they load in platform processes. None has been installed on the iPhone during this publication pass.

## Published

- `com.ratush.iggridfeed` `0.5.2+rootless1`
- `com.ratush.appabetical` `1.0.16+rootless4`
- `com.ratush.ccgapcloser` `0.4.7+rootless3`
- `com.ratush.jetsamfix` `1.0.1+rootless1`
- `com.ratush.safeguard` `1.2.1+rootless1`
- `com.ratush.crontweak` `1.2.0+rootless1`
- `com.ratush.catmcpcc` `1.0.0+ratu10+rootless1`
- `com.ratush.ccopenssh` `1.0.10+rootless1`

## Existing rootless packages to audit, not replace

- `com.ratush.hppe` (user-maintained current rootless build)
- `com.ratush.tgproxyrotation`
- `ru.danpashin.twackup` and `ru.danpashin.twackup-gui`
- `com.ratush.catmcp-rootless-fix`

## Blocked by missing source or rootless base

- `com.ratush.vpnappbridge`: depends on `com.snail.autovpn.global`; only a RootHide arm64e binary is present and no source is available.
- `com.snail.autovpn.global`, `com.level3tjg.offloader`, `com.choco.tg`, `com.netskao.appdata`, `com.noisyflake.albummanager`, and `xyz.cypwn.cr4shed`: no owned buildable source in this repository.

## Remaining owned-source migrations

- `com.ratush.etchosts17`
- `com.ratush.cchppe`
- remaining Control Center and network integrations after their runtime dependencies are audited.
