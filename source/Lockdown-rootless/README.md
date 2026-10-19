# lockdown for Dopamine rootless

Port of roothide/lockdown 2.0, upstream eab851c7ac6b295cd418882f3270c1fde4f8cc6e.
Original author: roothide. Port: chelaxian. GPL-3.0; see LICENSE.
Upstream: https://github.com/roothide/lockdown

## Package and target

- com.ratush.lockdown, version 2.0+rootless1, Debian architecture iphoneos-arm64.
- Ordinary Dopamine 3 rootless / ElleKit, iOS 17.0; package excludes 17.1+.
- Dylib slices: arm64 and arm64e with PAC ABI (0x80000002).
- Injection only into com.apple.WebKit.WebContent.
- Payload: /var/jb/Library/MobileSubstrate/DynamicLibraries/lockdown2.{dylib,plist}.
  The bootstrap may expose this through /var/jb/usr/lib/TweakInject.

## Behavior and limitations

Preserves upstream WebContent level 1 (Balanced): JSC_forceGCSlowPaths=true,
JSC_useConcurrentGC=false, reinforcement through JSC::Options after initialize,
and haveABadTime(VM&) after JSGlobalObject::init. JIT remains enabled. There is no
Settings pane or preference reader; the level is a compile-time constant.

This is JavaScriptCore hardening, not Apple's system Lockdown Mode, a WebKit
update or a guarantee against all exploits. JavaScript performance may change.
No exploit-resistance or performance claim has been validated on the device yet.

Removes RootHide Bootstrap's host-app XPC environment injection path, the
webcontent_environs export, roothide.h, jbroot(), Bootstrap marker detection and
the broad com.apple.WebKit bundle filter. The native WebContent hook path is
retained. No jailbreak bootstrap modifications or privileged helper are added.

Private symbols are resolved before changing the environment or installing hooks.
If required symbols are absent, protection remains INACTIVE and a warning is
logged; upstream abort() is removed to preserve process availability. Unified
logging replaces the RootHide file logger. Accepted/rejected options, hook setup
and the first five haveABadTime calls are logged with [lockdown-rootless].

Actual coverage depends on Dopamine/ElleKit and per-process injection policy.
A package installed successfully or a Hooks installed log does not establish
runtime enforcement. Reaching both hooks in a fresh process must be observed.

## Build and static checks

Use .github/workflows/build.yml (macOS 15 / Apple Xcode clang, pinned Theos).
CI records source/toolchain versions, builds and signs the package, then runs
scripts/verify_deb.py on its extracted contents. This checks metadata, exact filter,
rootless layout/libraries, both Mach-O slices, arm64e PAC ABI and signatures.
CI uploads an artifact; it does not publish to an APT repository.

    THEOS="$HOME/theos" make clean package FINALPACKAGE=1
    tmp="$(mktemp -d)"
    dpkg-deb -x packages/com.ratush.lockdown_2.0+rootless1_iphoneos-arm64.deb "$tmp"
    dpkg-deb -e packages/com.ratush.lockdown_2.0+rootless1_iphoneos-arm64.deb "$tmp/DEBIAN"
    python3 scripts/verify_deb.py "$tmp"

WSL compile/package preflight is supported. Its plain arm64e subtype 0x00000002
is rejected; do not install that artifact into the target platform process.
Use the inspected macOS artifact and compare its SHA256SUMS.

## Device validation: pending

Verify model/iOS/build, active Dopamine >=3.0.7, /var/jb, package architecture,
ElleKit, sudo and existing/conflicting package versions before installation.
Preserve the previous DEB when updating; never downgrade a newer build or remove
a conflicting package automatically. Install through the rootless package manager.

Scripts do not kill active browsing sessions. Close/reopen Safari and WebView
apps, verifying that a genuinely fresh WebContent PID was launched. Confirm
ElleKit and lockdown2.dylib are loaded. Observe accepted options and haveABadTime
calls while testing Safari and an embedded WKWebView, navigation, JavaScript,
media, enabled/disabled behavior and new crash reports. Module presence alone
is not behavioral proof. If the device has the log utility:

    log stream --level debug --predicate 'eventMessage CONTAINS "[lockdown-rootless]"'

Rollback: remove ONLY com.ratush.lockdown (or reinstall the preserved previous
DEB for an update), then restart affected browser/WebContent processes narrowly.
Existing processes retain loaded code/options until exit. New processes return
to stock JSC behavior. No system files or persistent preferences are changed.
Preserve SSH and the package manager throughout testing.
