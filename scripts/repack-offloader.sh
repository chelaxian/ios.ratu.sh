#!/usr/bin/env bash
set -euo pipefail

input_deb=$1
runtime_deb=$2
output_deb=$3
version=$4
workdir=${5:-/tmp/offloader-repack}

rm -rf "$workdir"
mkdir -p "$workdir/root" "$workdir/control" "$workdir/runtime"

dpkg-deb -x "$input_deb" "$workdir/root"
dpkg-deb -e "$input_deb" "$workdir/control"
dpkg-deb -x "$runtime_deb" "$workdir/runtime"

cp "$workdir/runtime/Library/MobileSubstrate/DynamicLibraries/OffloaderRuntimeFix.dylib" \
    "$workdir/root/Library/MobileSubstrate/DynamicLibraries/OffloaderRuntimeFix.dylib"
sed -i "s/^Version: .*/Version: $version/" "$workdir/control/control"

(
    cd "$workdir/root"
    find . -type f -print0 |
        sort -z |
        while IFS= read -r -d '' file; do
            md5sum "$file" | sed 's#  ./#  #'
        done > "$workdir/control/md5sums"
)

mkdir -p "$workdir/package/DEBIAN"
cp -a "$workdir/control/." "$workdir/package/DEBIAN/"
cp -a "$workdir/root/." "$workdir/package/"
chmod 755 "$workdir/package/DEBIAN"
chmod 644 "$workdir/package/DEBIAN/"*

mkdir -p "$(dirname "$output_deb")"
dpkg-deb -Zgzip -b "$workdir/package" "$output_deb"
