#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  echo "dpkg-scanpackages is required" >&2
  exit 1
fi

dpkg-scanpackages -m debs /dev/null > Packages

# Normalize flavour suffixes in repository display versions for tweaks only.
python3 - <<'PY'
from pathlib import Path
import re
p = Path('Packages')
s = p.read_text(encoding='utf-8')
stanzas = re.split(r'(?=^Package: )', s, flags=re.M)
out = []
for stanza in stanzas:
    if re.search(r'(?m)^Section: Tweaks$', stanza):
        def clean(m):
            value = m.group(1)
            base = value.split('+', 1)[0]
            return 'Version: ' + (base + '+rh' if '+rh' in value else base)
        stanza = re.sub(r'(?m)^Version: ([^\r\n]+)$', clean, stanza)
    out.append(stanza)
p.write_text(''.join(out), encoding='utf-8')
PY

bzip2 -c9 Packages > Packages.bz2
gzip -c9n Packages > Packages.gz

python3 - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import hashlib

files = ["Packages", "Packages.bz2", "Packages.gz"]

def digest(path, algorithm):
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

lines = [
    "Origin: ios.ratu.sh",
    "Label: ios.ratu.sh",
    "Suite: stable",
    "Version: 2.0",
    "Codename: ios",
    "Architectures: iphoneos-arm64 iphoneos-arm64e",
    "Components: main",
    "Description: Rootless and RootHide jailbreak packages",
    f"Date: {datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')}",
]

for label, algorithm in [("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")]:
    lines.append(f"{label}:")
    for name in files:
        path = Path(name)
        lines.append(f" {digest(path, algorithm)} {path.stat().st_size:16d} {name}")

Path("Release").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
