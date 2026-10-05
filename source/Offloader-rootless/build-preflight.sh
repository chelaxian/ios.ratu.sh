#!/usr/bin/env bash
set -euo pipefail
src="$(cd -- "$(dirname -- "$0")" && pwd)"
build="$(mktemp -d /tmp/offloader-preflight.XXXXXX)"
trap 'rm -rf "$build"' EXIT
cp "$src"/{Makefile,control,OFShared.h,OFHook.h,OFApplications.h,OFNativeOffload.h,OFAppStore.h,OFGuard.m,OFBridge.m,OFSpringBoard.m,Offloader.plist,OffloaderGuard.plist} "$build/"
cp -R "$src/Preferences" "$src/layout" "$build/"
python3 - "$build" <<'PY'
import pathlib, sys
for path in pathlib.Path(sys.argv[1]).rglob('*'):
    if path.is_file():
        path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
PY
cd "$build"
THEOS="${THEOS:-/opt/theos}" make clean package FINALPACKAGE=1
mkdir -p "$src/diagnostics/preflight"
cp packages/*.deb "$src/diagnostics/preflight/"
echo 'Preflight only: use the macOS/Xcode artifact for iOS platform processes.'
