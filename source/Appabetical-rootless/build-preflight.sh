#!/usr/bin/env bash
set -euo pipefail
src="$(cd -- "$(dirname -- "$0")" && pwd)"
build=/root/iosdev/appabetical-dopamine-20261005
mkdir -p "$build"
cp "$src"/{Tweak.x,ABEngine.m,ABPreferences.m,ABShared.h,Makefile,control,Appabetical.plist} "$build/"
cp -R "$src/AppabeticalPrefs" "$build/"
python3 - "$build" <<'PY'
import pathlib, sys
for path in pathlib.Path(sys.argv[1]).rglob('*'):
    if path.is_file() and (path.suffix in {'.m','.h','.x','.plist','.strings'} or path.name in {'Makefile','control'}):
        path.write_bytes(path.read_bytes().replace(b'\r\n',b'\n'))
PY
cd "$build"
THEOS=/opt/theos make clean package FINALPACKAGE=1
mkdir -p "$src/diagnostics/preflight"
cp packages/*.deb "$src/diagnostics/preflight/"
