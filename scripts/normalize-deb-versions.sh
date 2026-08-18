#!/usr/bin/env bash
set -euo pipefail
for deb in debs/*.deb; do
  case "$deb" in
    *com.roothide*|debs/roothide_*) continue ;;
  esac
  tmp=$(mktemp -d)
  dpkg-deb -R "$deb" "$tmp"
  version=$(sed -n 's/^Version: //p' "$tmp/DEBIAN/control")
  version=$(printf '%s' "$version" | sed -E 's/\+rootless[0-9]*$//; s/\+roothide[^+]*$/+rh/')
  sed -i "s/^Version:.*/Version: $version/" "$tmp/DEBIAN/control"
  out="$deb.norm.deb"
  dpkg-deb -b "$tmp" "$out" >/dev/null
  mv "$out" "$deb"
  rm -rf "$tmp"
done
