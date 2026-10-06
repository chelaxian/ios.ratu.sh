# Adytum Fix validation — 2026-10-06

- Device: iPhone15,3, iOS 17.0 build 21A329, Dopamine 3.0.10, ElleKit 1.2.
- Original package: com.kernelrw.adytum 1.1. Original binary SHA256: 9c979663b8ff5447f6fe741e56bbcb1601ef562c16e2e2ada8738399f35aaeab.
- Supported arm64e UUID: 5FFA5340-E6C8-3E5B-9084-089FD354EFB3.
- Build: https://github.com/chelaxian/ios.ratu.sh/actions/runs/37473286270, source 3dc99dc.
- Artifact: com.ratush.adytumfix_1.0.0_iphoneos-arm64.deb, 5054 bytes.
- SHA256: e1229079f975c4b9876b6475c83c3e0db1cd9e353d16a6ce894a170144a9b840.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Build / current ABI | PASS | Xcode CI, arm64 + PTRAUTH arm64e; subtype 0x80000002 |
| DEB inspection | PASS | rootless paths, metadata, single dylib, signed code page hashes |
| Physical arm64e repair regression | PASS | 1006 assertions in temporary Preferences-only module; result 0, captured objects finalized |
| Injection in SpringBoard | PASS | log shows UIAction=1, spring=1, animation=1 |
| Real Adytum blocks repaired | PASS | eight repair markers from UUID-gated helper |
| Long press and menu action | PASS | owner: “Да, меню и действие работают” |
| SpringBoard survival | PASS during observed checks | PID41961 survived; newest crash stayed SpringBoard-2026-10-06-153831.ips |
| Temporary module removal | PASS | AdytumFixCheck dylib and filter removed before production installation |

## Device regression output

```text
PASS: 1006 arm64e assertions; repaired blocks copy and execute, UIAction and both UIView routes accept them.
PASS: captured object lifetimes preserved.
RESULT=0
```

The first candidate used the DB key. The regression rejected it at signature equality; it was not installed in SpringBoard. Corrected to DA, matching compiler-generated block isa signatures.

A standalone arm64e CLI was killed at launch (137), even after adding its exact CDHash to the trust cache. It never entered the test, so it is not counted as a repair test. The passing test was run inside the actual arm64e Preferences process, without Frida. No new Preferences or SpringBoard crash appeared during the passing test.

The companion package does not include or modify Adytum. For the live long press check only show3DTouchMenu was changed from false to true; other Adytum settings were preserved. The user confirmed the now-enabled feature works.

The fixed paths are the recorded icon UIAction and UIView spring/non-spring animation routes. This is not a claim that every unrelated Adytum feature or an untested newer build is fixed. Rollback: disable Adytum menu, uninstall com.ratush.adytumfix, respring.
