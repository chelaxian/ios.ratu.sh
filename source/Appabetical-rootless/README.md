# Appabetical for Dopamine

GPLv3 rewrite of the RootHide adaptation of [Avangelista/Appabetical](https://github.com/Avangelista/Appabetical), by Avangelista and sourcelocation. Layout presets were inspired by [OwnGoalStudio/IconRestore](https://github.com/OwnGoalStudio/IconRestore).

## Runtime

The tweak runs in SpringBoard on iOS 17. It sorts the actual `SBFolder` hierarchy using `swapIconAtIndexPath:withIconAtIndexPath:options:` and persists it using `saveIconStateIfNeeded`. Sorting does not respring. Widgets, placeholder icons, excluded folders and the excluded dock retain their slots. Folders stay intact; folder contents are sorted across their existing pages without assuming a fixed capacity.

Order: optional bookmarks/offloaded end groups, applications, folders, Shortcuts, Latin, Cyrillic, other scripts in stable order; names use case and diacritic insensitive numeric comparison. Offloaded apps are resolved even when their icon has no live `SBApplication`. Emoji filtering works on Unicode scalars and retains nonemoji supplementary characters.

Switches: Enabled, offloaded apps last, bookmarks last, ignore emoji, sort folder icons, sort folder contents, include dock, autosort on respring. Changes apply to the next sort; autosort runs once when SpringBoard's model is ready. The language menu changes the preference panel between English and Russian.

## Presets

SpringBoard owns `/var/mobile/Library/SpringBoard/AppabeticalPresets.plist`. Preferences sends UUID tagged requests through CFPreferences and Darwin notifications. Every action waits for a matching response. Catalog updates come from SpringBoard; Preferences does not directly modify the private preset file. Failed writes and timeouts are reported as failures.

New presets have `@appab_format = 3`, `iconState` and optional Control Center dictionaries. Bare v1 and enveloped v2 states remain readable. Duplicate names require overwrite confirmation. Deletion uses the same acknowledged command channel.

Snapshots flush the live model before reading its store. Restore validates the full multiset of apps, folders and widget data. Changed inventories are rejected, so apps added since saving are preserved. Before a mutation the tweak keeps a layout backup in `/var/mobile/Library/SpringBoard/AppabeticalRecovery/<UUID>/IconState.plist`.

Control Center's active configuration URL comes from `CCSModuleSettingsProvider`. On this device CCSupport redirects its file into the Dopamine overlay. Presets store its data, not the preboot UUID. Restore commits the state through `SBDefaultIconModelStore`, restarts SpringBoard, skips autosort for that restoration, and acknowledges success after the next process verifies the layout. `/var/mobile/Library/SpringBoard/AppabeticalRestore.plist` is the transaction checkpoint.

## Build

The DEB architecture is `iphoneos-arm64`; both binaries include `arm64` and current `arm64e` slices for platform processes.

```sh
THEOS="$HOME/theos" make clean package FINALPACKAGE=1
```

Use macOS/Xcode for device artifacts. The GitHub workflow `.github/workflows/build-appabetical-rootless.yml` requires PTRAUTH subtype `0x80000002` for both the tweak and preference bundle. WSL output is for compilation preflight only. `build-preflight.sh` copies just the build sources to a path without spaces and normalizes CRLF.

Inspect a downloaded artifact before installing:

```sh
python diagnostics/inspect_deb.py packages/com.ratush.appabetical_VERSION_iphoneos-arm64.deb
```

## Validation and recovery

See `VALIDATION-20261005.md` for device evidence, known conflict and rollback. Validation scripts and private device snapshots are in the local `diagnostics` directory and are not included in the package or public source branch.

Log: `/var/mobile/Library/Preferences/com.ratush.appabetical.debug.log` (bounded to 1 MiB).
