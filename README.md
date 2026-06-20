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

- HPPE and CCHPPE
- Twackup CLI and GUI
- Offloader and libMRYIPC
- CatMCP and its RootHide companion
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
