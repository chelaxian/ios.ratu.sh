#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

export THEOS="${THEOS:-/root/roothide-theos-codex}"
export THEOS_PACKAGE_SCHEME=roothide

make clean
make package FINALPACKAGE=1

ls -la packages/*.deb
