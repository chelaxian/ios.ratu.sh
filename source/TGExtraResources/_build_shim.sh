#!/usr/bin/env bash
# Build TGExtraResources.dylib from TGExtraResources.m
# Prereqs: theos toolchain (clang/lipo/ldid/otool/nm), iPhoneOS SDK.
set -euo pipefail
TC="${TC:-$HOME/theos/toolchain/linux/iphone/bin}"
SDK="${SDK:-$HOME/theos/sdks/iPhoneOS16.5.sdk}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$HERE/TGExtraResources.m}"
OUT="${OUT:-$HERE/TGExtraResources.dylib}"
W="$HOME/tgx-shim-build"
rm -rf "$W"; mkdir -p "$W"; cd "$W"

clang() { "$TC/clang" "$@"; }
lipo()  { "$TC/lipo"  "$@"; }
ldid()  { "$TC/ldid"  "$@"; }

echo ">> compile arm64"
clang -target arm64-apple-ios14.0 -isysroot "$SDK" -fobjc-arc -fobjc-weak \
  -dynamiclib -install_name @rpath/TGExtraResources.dylib \
  -framework Foundation -framework UIKit -o TGExtraResources.arm64.dylib "$SRC"

echo ">> compile arm64e"
clang -target arm64e-apple-ios14.0 -isysroot "$SDK" -fobjc-arc -fobjc-weak \
  -dynamiclib -install_name @rpath/TGExtraResources.dylib \
  -framework Foundation -framework UIKit -o TGExtraResources.arm64e.dylib "$SRC"

echo ">> lipo -> fat"
lipo -create TGExtraResources.arm64.dylib TGExtraResources.arm64e.dylib -output TGExtraResources.dylib

echo ">> adhoc sign"
ldid -S TGExtraResources.dylib
cp TGExtraResources.dylib "$OUT"
echo ">> wrote $OUT"
sha256sum "$OUT"
