# AddToFolder Fix — Dopamine / iOS 17

Independent compatibility layer for AnthoPak's **AddToFolder 1.4**. Install
alongside the original tweak. It preserves the original menu item, its custom
text, position and preference panel, and replaces its folder picker and moves.
No original AddToFolder binaries or source code are redistributed here.

## Changes

- Enumerates folders reachable from the **live Home Screen and dock**, instead
  of reading the global `SBIconModel._folders` registry, which also includes
  cached/archived layouts.
- Deduplicates by folder identity. Two real folders with the same name remain
  distinct and receive a location suffix.
- Resolves the selected folder again by identity at the moment of movement.
  It never chooses a destination by display name.
- Moves through the live `SBFolder` model APIs available on iOS 17. It checks
  the actual final container, the number of icon positions and the complete
  non-folder icon inventory before reporting success.
- Preserves creating a new folder, removing an icon from its current folder,
  and moving to an existing Home Screen page.
- Checks method encodings at runtime, including the IN/OUT index-path pointer
  required by `insertIcon:atIndexPath:options:`.
- Writes a recovery snapshot before any mutation. Attempts a narrow rollback
  on error and shows the error instead of silently claiming a successful move.
- Intercepts only `CustomAddToFolderItem`; other app/tweak quick actions keep
  their existing handler chain. Hooks are installed after dylib constructors.

Recovery snapshots: `/var/mobile/Library/SpringBoard/AddToFolderFixRecovery/<UUID>/IconState.plist`.
Diagnostics: SpringBoard system log entries prefixed `[AddToFolderFix]`.

## Build

Rootless package `com.ratush.addtofolderfix`, architecture `iphoneos-arm64`;
the dylib contains both `arm64` and current ABI `arm64e` slices. Use the macOS
GitHub Actions artifact for installation. WSL builds are compilation preflight
only and must not be installed into SpringBoard.

## Installation / rollback

Install **AddToFolder Fix 1.0.0** from `https://ios.ratu.sh/`, leaving AddToFolder
1.4 installed, and restart SpringBoard. No Appabetical update is required.
Removing only `com.ratush.addtofolderfix` and restarting SpringBoard restores
the original AddToFolder handler; its preferences remain in place.

## Validation boundary

The original 1.4 binary was inspected locally. Its global `_folders` lookup,
name-based destination selection, legacy `SBHIconManager` move selectors and
IN/OUT index-path use were identified in ARM64 disassembly. The iOS 17 live
folder APIs were cross-checked against runtime metadata previously collected
during the Appabetical work. The relationship between Appabetical sorting and
the appearance of cached folders is **not proven** without a new runtime probe.

**Device behavior remains NOT TESTED:** the owner has prohibited further
device access during this work. Compilation and artifact inspection do not
prove that the UI or model mutations work on the owner's current device.
The owner should check a single entry per actual folder, a move followed by a
SpringBoard restart, new-folder creation, removal, page movement, offloaded
apps/bookmarks, and Appabetical sorting/preset restoration afterward.

Original package/support: https://repo.anthopak.dev/depiction/web/com.anthopak.addtofolder-rootless.php
