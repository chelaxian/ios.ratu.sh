#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${EtcHosts17_BUILD_COPY:-}" ]]; then
	source_dir="$PWD"
	control_mode="$(stat -c '%a' layout/DEBIAN 2>/dev/null || printf '')"
	if [[ "$source_dir" == *" "* || "$control_mode" == "777" ]]; then
		work="$(mktemp -d /tmp/EtcHosts17-build.XXXXXX)"
		trap 'rm -rf "$work"' EXIT
		tar --exclude=.theos --exclude=packages --exclude=.research -cf - . | tar -C "$work" -xf -
		find "$work" -type d -exec chmod 0755 {} +
		find "$work" -type f -exec chmod 0644 {} +
		chmod 0755 "$work/build.sh"
		chmod 0755 "$work/layout/DEBIAN/postinst" "$work/layout/DEBIAN/postrm" "$work/layout/DEBIAN/prerm"
		(
			cd "$work"
			EtcHosts17_BUILD_COPY=1 EtcHosts17_SOURCE_DIR="$source_dir" bash ./build.sh
		)
		mkdir -p "$source_dir/packages"
		cp -f "$work"/packages/*.deb "$source_dir/packages/"
		printf 'Copied package(s) to %s/packages\n' "$source_dir"
		exit 0
	fi
fi

export THEOS_PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-roothide}"

make clean package FINALPACKAGE=1

pkg="$(ls -t packages/*.deb | head -n 1)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

dpkg-deb -R "$pkg" "$work"
install -m 0755 layout/DEBIAN/postinst "$work/DEBIAN/postinst"
install -m 0755 layout/DEBIAN/postrm "$work/DEBIAN/postrm"
install -m 0755 layout/DEBIAN/prerm "$work/DEBIAN/prerm"

(
	cd "$work"
	find . -path ./DEBIAN -prune -o -type f -print0 |
		sort -z |
		while IFS= read -r -d '' f; do
			md5sum "$f" | sed 's#  \./#  #'
		done > DEBIAN/md5sums
)

dpkg-deb -Zgzip --root-owner-group -b "$work" "$pkg"
dpkg-deb --info "$pkg" | grep -E '(^ Package:|^ Version:|^ Architecture:|postinst|postrm)' || true
printf 'Built %s\n' "$pkg"
