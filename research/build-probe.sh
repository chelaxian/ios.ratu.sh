#!/bin/bash
set -eu
T="$HOME/theos"
"$T/toolchain/linux/iphone/bin/clang" -target arm64-apple-ios15.0 -isysroot "$T/sdks/iPhoneOS16.5.sdk" -fobjc-arc -framework Foundation ne-probe.m -o ne-probe
"$T/toolchain/linux/iphone/bin/ldid" -Cadhoc -Sprobe.entitlements.plist ne-probe
