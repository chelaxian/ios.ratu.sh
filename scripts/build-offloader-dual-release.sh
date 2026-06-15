#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <release-number> <rootless-base.deb> <roothide-base.deb>" >&2
    exit 1
fi

release=$1
rootless_base=$(realpath "$2")
roothide_base=$(realpath "$3")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir=$(mktemp -d)
toolchain=${THEOS:-"$HOME/theos"}/toolchain/linux/iphone/bin

trap 'rm -rf "$workdir"' EXIT

for file in "$rootless_base" "$roothide_base"; do
    test -f "$file" || { echo "Missing base package: $file" >&2; exit 1; }
done

normalize_sources() {
    local directory=$1
    find "$directory" -type f \
        \( -name Makefile -o -name control -o -name '*.m' -o \
           -name '*.xm' -o -name '*.plist' \) \
        -exec sed -i 's/\r$//' {} +
}

build_component() {
    local project=$1
    local scheme=$2
    local output=$3
    local build_dir="$workdir/build-$scheme-$project"

    cp -a "$repo_root/source/$project" "$build_dir"
    normalize_sources "$build_dir"
    (
        cd "$build_dir"
        export THEOS=${THEOS:-"$HOME/theos"}
        gmake clean package FINALPACKAGE=1 \
            THEOS_PACKAGE_SCHEME="$scheme" \
            ARCHS="arm64 arm64e"
    )
    cp "$build_dir"/packages/*.deb "$output"
}

make_md5sums() {
    local package_root=$1
    (
        cd "$package_root"
        find . -path ./DEBIAN -prune -o -type f -exec md5sum {} \; |
            sed 's#  \./#  #' > DEBIAN/md5sums
    )
}

repack() {
    local package_root=$1
    local output=$2
    chmod 755 "$package_root/DEBIAN"
    chmod 644 "$package_root/DEBIAN/"*
    dpkg-deb -Zgzip -b "$package_root" "$output"
}

projects=(
    OffloaderVanillaCapture
    OffloaderRuntimeFix
    OffloaderAntiOffloadFix
    OffloaderPrefsFix
)

for scheme in rootless roothide; do
    mkdir -p "$workdir/components-$scheme"
    for project in "${projects[@]}"; do
        build_component \
            "$project" \
            "$scheme" \
            "$workdir/components-$scheme/$project.deb"
    done
done

mkdir -p "$workdir/rootless/DEBIAN" "$workdir/roothide/DEBIAN"
dpkg-deb -x "$rootless_base" "$workdir/rootless"
dpkg-deb -e "$rootless_base" "$workdir/rootless/DEBIAN"
dpkg-deb -x "$roothide_base" "$workdir/roothide"
dpkg-deb -e "$roothide_base" "$workdir/roothide/DEBIAN"

for scheme in rootless roothide; do
    for project in "${projects[@]}"; do
        component_root="$workdir/component-$scheme-$project"
        mkdir -p "$component_root"
        dpkg-deb -x \
            "$workdir/components-$scheme/$project.deb" \
            "$component_root"
        if [[ "$scheme" == rootless ]]; then
            cp -a "$component_root/var/jb/." "$workdir/rootless/var/jb/"
        else
            cp -a "$component_root/Library/." "$workdir/roothide/Library/"
        fi
    done
done

rootless_prefs="$workdir/rootless/var/jb/Library/PreferenceBundles/OffloaderPrefs.bundle/OffloaderPrefs"
if "$toolchain/otool" -L "$rootless_prefs" |
        grep -q '@loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList'; then
    "$toolchain/install_name_tool" \
        -change @loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList \
        @rpath/AltList.framework/AltList \
        "$rootless_prefs"
    "$toolchain/ldid" -S "$rootless_prefs"
fi

sed -i \
    -e "s/^Version: .*/Version: 0.0.6+rootless$release/" \
    -e 's/^Architecture: .*/Architecture: iphoneos-arm64/' \
    -e 's/^Description: .*/Description: Offload apps from the 3D touch menu and more (rootless)/' \
    "$workdir/rootless/DEBIAN/control"
sed -i \
    -e "s/^Version: .*/Version: 0.0.6+roothide$release/" \
    -e 's/^Architecture: .*/Architecture: iphoneos-arm64e/' \
    -e 's/^Description: .*/Description: Offload apps from the 3D touch menu and more (RootHide adapted)/' \
    "$workdir/roothide/DEBIAN/control"

rootless_output="$repo_root/debs/com.level3tjg.offloader_0.0.6+rootless${release}_iphoneos-arm64.deb"
roothide_output="$repo_root/debs/com.level3tjg.offloader_0.0.6+roothide${release}_iphoneos-arm64e.deb"

make_md5sums "$workdir/rootless"
make_md5sums "$workdir/roothide"
repack "$workdir/rootless" "$rootless_output"
repack "$workdir/roothide" "$roothide_output"

echo "$rootless_output"
echo "$roothide_output"
