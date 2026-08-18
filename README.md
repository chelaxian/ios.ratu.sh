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
- Claude Code iOS — NewTerm 3 `ssh://` launcher (arm64)

The website reads `Packages` directly and merges architecture variants into one
catalog entry. Adding or removing a package therefore does not require editing the
HTML package list. Tweak names and the per-architecture tags next to each entry
are direct download links to the `.deb` file (the name links to the first
variant; each architecture tag links to its own `.deb`).

## Dylibs (sideload / TrollFools)

The `Dylibs` section lists standalone `.dylib` files for injection via
Sideloadly / TrollFools / TrollStore — i.e. without a jailbreak. Dylibs are not
part of the APT index, so they are described by a separate manifest,
[`dylibs.json`](dylibs.json), which the website loads at runtime.

To publish a dylib:

1. Drop the file into `sideload/` (e.g. `sideload/TGProxyRotation-0.14.0.dylib`).
2. Append an entry to `dylibs.json` — `filename`, `size`, and `sha256` of the
   file, plus `tags` (typically `["sideload", "trollfools", "dylib"]`). The
   `description` normally mirrors the corresponding tweak's `Description` from
   `Packages`.
3. Commit and push — no index rebuild is needed.

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


## Claude Code iOS

`com.ratush.claude-code-ios` packages Claude Code 2.1.112 for rootless iOS with
the bundled iOS Node runtime and an iOS-patched ripgrep. Its home-screen launcher
opens **NewTerm 3** through its supported `ssh://` URL scheme and then starts
Claude Code in the terminal. This replaces the old unregistered `newterm3://`
URL that caused the original launcher to quit immediately.

**Requirements:** NewTerm 3, OpenSSH, and a rootless jailbreak. The package sets
up a dedicated, forced-command local SSH key automatically; it preserves existing
SSH keys and config. After installation, authenticate once in NewTerm:

```sh
claude-auth
```

Then tap **Claude Code** on the home screen to open NewTerm directly into Claude.

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

## Safeguard

`com.ratush.safeguard` — proactive memory-pressure watchdog that complements
JetsamFix. Where JetsamFix holds a *passive* policy floor (raised limits +
lenient mode), Safeguard actively *detects and remediates* pressure events:
it samples RAM pressure and resident processes every ~20 s and, once the device
is under pressure (jetsam AMBER or RED zone), SIGKILLs allowlisted debug-daemon
hogs that have *ballooned* past an RSS floor (default target: a leftover
`frida-server`/`frida-helper` — the classic hidden hog that tips a
heavily-tweaked device into recurring safe mode).

Key properties:

- **Detection is syscall-only** (`host_statistics64` for free/purgeable/swap,
  `proc_pidinfo` for per-process RSS) and so works from the launchd daemon's
  data-container namespace where file reads fail.
- **Pressure zones:** AMBER at free+purgeable < 120 MB, RED below 60 MB. Acting
  at AMBER, not only at RED, because a memory-starved process can SIGSEGV
  before free memory ever crosses the RED line — the case-study Safe-Mode
  crash was exactly such a pressure-starvation SIGSEGV, not a jetsam relaunch.
- **RSS floor:** an allowlisted hog is only killed when its RSS is at least
  `kill_min_rss_mb` (default 100 MB). A small/idle instance you still need (a
  `frida-server` resting at ~10 MB) is tolerated and logged as `tolerated`;
  only a ballooned one (150 MB+) is killed.
- **Safety:** only names on the kill-allowlist are ever touched; SpringBoard,
  backboardd, launchd, kernel_task, etc. are on an explicit never-kill list and
  cannot be auto-killed.
- **Auditable:** the daemon logs the name/pid/rss of any kill-allowlisted
  process it sees, and the zone transitions; steady state is log-silent.
- **Self-protecting:** it lifts its own launchd jetsam cap at startup so the
  watchdog itself is not jetsammed.
- It runs as a `Depends: com.ratush.jetsamfix` companion.

### CLI control

`safeguard status` — current zone, free/swap, vm pressure level, top hogs by
RSS, and posture (armed/disarmed).

`safeguard top [N]` — top-N processes by resident size.

`safeguard check` — one-shot detect pass (never kills).

`safeguard kill <name|pid>` — manually SIGKILL a hog; **refused unless the
name is on the kill-allowlist** (so a system process can never be killed by
mistake).

`safeguard arm` / `safeguard disarm` — resume / suspend the daemon's auto-kill
(via SIGUSR1/SIGUSR2).

### Rollback

`sudo dpkg -r com.ratush.safeguard` — the `prerm` script does the
`launchctl bootout`. (Leave JetsamFix installed; it is independent.)
