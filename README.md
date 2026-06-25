# ios.ratu.sh

Personal APT repository for RootHide Bootstrap and modern rootless jailbreaks.

Repository URL: `https://ios.ratu.sh/`

## Package layout

| Architecture | Environment |
| --- | --- |
| `iphoneos-arm64e` | RootHide Bootstrap |
| `iphoneos-arm64` | Standard rootless jailbreaks |

User-facing tweaks use `Section: Tweaks`. Development tools, package-management
utilities, libraries, and system components retain their functional sections so
Sileo can group them predictably.

Current project families:

- Hidden Photos Manager and CCHPM
- Twackup CLI and GUI
- Offloader and libMRYIPC
- CatMCP and its RootHide companion
- JetsamFix (memory manager / OOM protection)
- RootHide development and recovery toolchain

The website reads `Packages` directly and merges architecture variants into one
catalog entry. Adding or removing a package therefore does not require editing the
HTML package list.

## Publishing

Place release archives in `debs/`, remove superseded versions, then rebuild all
indexes from the repository root:

```sh
scripts/build-index.sh
```

Validate the generated metadata before committing:

```sh
grep -E '^(Package|Name|Version|Architecture|Section|Filename|SHA256):' Packages
```

`Release` advertises both supported architectures and contains checksums for
`Packages`, `Packages.gz`, and `Packages.bz2`.

## JetsamFix

`com.ratush.jetsamfix` — memory-manager daemon for RootHide Bootstrap that
prevents jetsam / OOM crashes (the safe-mode / respring loops that are really
caused by memory pressure, not by a broken tweak). It is the RootHide/iOS 17
successor to JetsamUnlimited (which only worked up to iOS 15.8.2).

A privileged launchd daemon (`jetsamfixd`) calls the kernel
`memorystatus_control()` syscall (gated by the
`com.apple.private.memorystatus` entitlement) and, every 30 s, re-applies:

- global **aggressive-lenient mode** ON — the primary OOM protection;
- SpringBoard's per-process fatal jetsam cap **removed** (`limit = 0`);
- backboardd priority raised to band 150;
- VPN packet tunnels (`NEPacketTunnelProvider`) hard cap raised to 256 MB
  (applied when a tunnel is running).

The daemon is self-sufficient: it carries a built-in policy so it works even
when the on-device config plist is unreachable, and it logs to the launchd
stderr redirect (compact, only on state changes) instead of a non-rotating
file.

### CLI control

`jetsamfix status` — show aggressive-lenient state and current VM pressure
level.

`jetsamfix apply` — apply the policy once and print per-target results.

`jetsamfix lenient on` / `jetsamfix lenient off` — toggle global
aggressive-lenient mode.

The daemon re-applies the full policy automatically every 30 s, so the CLI is
only for ad-hoc checks or one-off changes.

### Rollback

`sudo dpkg -r com.ratush.jetsamfix` — the `prerm` script does the
`launchctl bootout`; respring once and the default iOS jetsam limits return.
