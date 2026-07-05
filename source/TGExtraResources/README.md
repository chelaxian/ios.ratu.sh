# TGExtraResources — sideload localization shim for TGExtra.dylib

## Problem

`TGExtra.dylib` (com.choco.tg 1.2.1) loads its translations from:

    /Library/Application Support/TGExtra/TGExtra.bundle/<lang>.lproj/Localizable.strings
    /Library/Application Support/TGExtra/TGExtra.bundle/langs.json

When TGExtra is sideloaded (injected into Telegram/Swiftgram/Turrit IPA via
Sideloadly/TrollFools, NO jailbreak), that jailbreak-only path does not exist.
The tweak has a fallback to `[[NSBundle mainBundle] resourcePath]` (the host
app bundle), but the sideload only injects the dylib — not the resource bundle —
so the fallback also misses. Result:

- UI shows raw keys ("GHOST_MODE_SECTION_HEADER") instead of translations
- The language switcher throws "Failed to load language localization data"
- Only English is selectable (langs.json can't be read → hardcoded fallback)

## Fix

`TGExtraResources.dylib` embeds all 10 language dictionaries compiled in
(~650 keys × 10 languages, ≈ 300 KB) and at runtime swizzles:

- `+[TGExtraLocalization localizedStringForKey:]` — the single `TGLoc(key)` funnel
- `-[LanguageSelector viewDidLoad]` — populate the language picker with all 10
- `-[LanguageSelector tableView:didSelectRowAtIndexPath:]` — load embedded dict on selection

so the whole tweak works under sideload with no resource bundle present.

## Build

Requires the theos toolchain and the upstream TGExtra sources (for the bundle):

    python3 _gen_shim.py        # parses TGExtra.bundle/*.strings → TGExtraResources.m
    wsl bash _build_shim.sh     # builds fat arm64+arm64e dylib, adhoc-signs

## Usage (sideload users)

Inject BOTH dylibs via Sideloadly or TrollFools:

1. `TGExtra-1.2.1.dylib` — the tweak itself
2. `TGExtraResources-1.2.1.dylib` — this localization shim

Loading order does not matter; the shim retries class resolution for ~8 seconds
after load to handle either dyld load order.

## License / attribution

Translations © waruhachi (https://github.com/waruhachi/TGExtra), used unmodified.
Shim code © chelaxian.
