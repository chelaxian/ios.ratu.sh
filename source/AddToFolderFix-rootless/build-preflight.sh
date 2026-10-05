#!/usr/bin/env bash
set -euo pipefail
src="$(cd -- "$(dirname -- "$0")" && pwd)"
build=/root/iosdev/addtofolderfix-20261005
mkdir -p "$build"
cp "$src"/{AddToFolderFix.m,AddToFolderFix.plist,Makefile,control} "$build/"
cd "$build"
THEOS=/opt/theos make clean package FINALPACKAGE=1
mkdir -p "$src/diagnostics/preflight"
cp packages/*.deb "$src/diagnostics/preflight/"
