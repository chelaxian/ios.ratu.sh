# AddToFolder Fix — 2026-10-05

## Evidence and diagnosis

The owner supplied screenshots showing every folder twice in the 1.4 picker,
and reported that choosing one does not move the icon. Device access is not
authorized in this task; the earlier prohibition remains in force.

Locally archived original binary:
`autovpn-work/installed/Library/MobileSubstrate/DynamicLibraries/AddToFolder.dylib`.
SHA256: `1b1be92fbe1114b948f9e270954b0392642c966fcde530a6a130c921c413c824`.

ARM64 disassembly identifies:

- `0x7518`: lookup of the private `SBIconModel._folders` instance variable.
- `0x7578` / objc stub `0xa180`: `allObjects`, with no filtering for folders
  reachable from the current Home Screen.
- `0x75b8`: mapping to display names; `0x75d0`: sorting the names.
- `0x84a8`–`0x84e4`: choosing the last folder whose display name equals the
  selected title. Distinct or stale folders with the same name are ambiguous.
- `0x86b8`–`0x87d0`: movement through the legacy `SBHIconManager` methods
  `addIcons:intoFolderIcon:openFolderOnFinish:completion:` or `...complete:`.
- `0x8b78`–`0x8b80`: page insertion passes the address of the index-path object
  correctly. It is an ABI requirement preserved by this fix, not an identified
  original defect.

The existing iOS 17.0 runtime dump from the Appabetical investigation lists the
live `SBFolder` methods used by this fix, including `canAddIcon:`,
`addIcon:options:`, `removeIcon:options:`, `indexPathForIcon:` and
`insertIcon:atIndexPath:options:`. Its `SBHIconManager` method list has no legacy
`addIcons:intoFolderIcon:...` entry. It does list folder creation. The current
SpringBoard delegate quick-action selector is also present.

Cached root-folder representations are a plausible reason for the global
registry returning two objects for each visible folder. The precise trigger
and its relationship to Appabetical 2.0.0 are not established by static data.
The fix avoids this registry completely and does not clear or mutate other
SpringBoard caches.

## Gates

| Gate | Result |
|---|---|
| Source review / original binary inspection | PASS |
| WSL compilation, arm64 + arm64e | PASS; platform ABI output is unsuitable for installation |
| macOS build and current arm64e ABI | PASS; macOS run 37326382100, PTRAUTH 0x80000002, both slices signed |
| APT publication and checksums | Repository release workflow generates the index; public hashes are checked during publication |
| Current-device injection and UI | NOT TESTED |
| Current-device moves / new folder / removal / pages | NOT TESTED |
| Current-device persistence and compatibility with Appabetical | NOT TESTED |

The package is an independently implemented companion, not a modified copy of
the closed-source original. Only this companion is published. It depends on
the original AddToFolder 1.4, keeps its menu/preferences and passes unrelated
quick actions through their existing hook chain.

Rollback: remove only `com.ratush.addtofolderfix` and restart SpringBoard.
Before mutation, the companion stores a layout snapshot under
`/var/mobile/Library/SpringBoard/AddToFolderFixRecovery/<UUID>/IconState.plist`.
No automatic full-model reload or external device-control operation is used.

Artifact: com.ratush.addtofolderfix_1.0.0_iphoneos-arm64.deb.
SHA256: b8179d19e23faba0b663a9e6c34ad5e967e052025a2707c11f46a8a4ddb70a50.
Build: https://github.com/chelaxian/ios.ratu.sh/actions/runs/37326382100 (success).
The first CI attempts failed on an incomplete source commit and lipo argument order; both were corrected before producing this artifact.
