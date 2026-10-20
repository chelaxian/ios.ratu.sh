#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  echo "dpkg-scanpackages is required" >&2
  exit 1
fi

dpkg-scanpackages -m debs scripts/overrides > Packages

# Normalize all repository display versions to their numeric portion.
python3 - <<'PY'
from pathlib import Path
import re
p = Path('Packages')
s = p.read_text(encoding='utf-8')
def clean(m):
    value = m.group(1)
    numeric = re.match(r'([0-9]+(?:\.[0-9]+)*(?:-[0-9]+)?)', value)
    return 'Version: ' + (numeric.group(1) if numeric else value)
# lockdown's Debian revision is part of its rootless release identity.
# Keep this package's version identical to the distributed DEB.
s = '\n\n'.join(
    block if re.search(r'(?m)^Package: com\.ratush\.lockdown$', block)
    else re.sub(r'(?m)^Version: ([^\r\n]+)$', clean, block)
    for block in s.split('\n\n')
)

# Repository categories are independent of upstream control metadata.
tweak_packages = {
    'com.thatmarcel.tweaks.neverheardofvpns',
    'me.jjolano.shadow',
}
blocks = []
for block in s.split('\n\n'):
    package = re.search(r'(?m)^Package: ([^\r\n]+)$', block)
    if package and package.group(1) in tweak_packages:
        if re.search(r'(?m)^Section:', block):
            block = re.sub(r'(?m)^Section: [^\r\n]*$', 'Section: Tweaks', block)
        else:
            block += '\nSection: Tweaks'
    blocks.append(block)
s = '\n\n'.join(blocks)
p.write_text(s, encoding='utf-8')
PY

# Publish English Name/Description in Packages (Sileo, Zebra). Russian texts live in
# i18n.json and are shown by the website when the RU language is selected.
python3 - <<'PY'
from pathlib import Path
import json, re
i18n = json.loads(Path('i18n.json').read_text(encoding='utf-8')).get('packages', {})
p = Path('Packages')
blocks = p.read_text(encoding='utf-8').split('\n\n')
def patch(block):
    m = re.search(r'(?m)^Package: (.+)$', block)
    en = i18n.get(m.group(1), {}).get('en') if m else None
    if not en:
        return block
    for field, value in en.items():
        pattern = r'(?m)^' + field + r': .*(?:\n[ \t].*)*'
        if re.search(pattern, block):
            block = re.sub(pattern, lambda _: field + ': ' + value, block, count=1)
    return block
p.write_text('\n\n'.join(patch(b) for b in blocks), encoding='utf-8')
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
