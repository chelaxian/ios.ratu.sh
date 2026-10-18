"""Verify the published Shadow release, dependency, and APT metadata."""
from concurrent.futures import ThreadPoolExecutor
import bz2
import gzip
import hashlib
from pathlib import Path
import time
import urllib.request

BASE = "https://ios.ratu.sh/"
EXPECTED = {
    "me.jjolano.shadow": (
        "4.0.0-1",
        "6bfb80b751bc61fced4ebf016d486cb72f813701af010fbe5ed7c6915c7ce625",
    ),
    "me.jjolano.fmwk.hookkit": (
        "3.0.5-1",
        "cab797601e64be87ba88f93fe536293af2d20750e8da84d32449df97824e435a",
    ),
}


def fetch(name):
    request = urllib.request.Request(
        BASE + name + "?shadow=" + str(time.time_ns()),
        headers={"Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        assert response.status == 200
        return response.read()


names = ["Packages", "Packages.gz", "Packages.bz2", "Release"]
with ThreadPoolExecutor(max_workers=4) as pool:
    blobs = dict(zip(names, pool.map(fetch, names)))
index = blobs["Packages"]
assert gzip.decompress(blobs["Packages.gz"]) == index
assert bz2.decompress(blobs["Packages.bz2"]) == index
source = Path(__file__).resolve().parents[1] / "Packages"
assert source.read_bytes() == index, "public index differs from checked-out source"

algorithm = None
checked = set()
for line in blobs["Release"].decode().splitlines():
    if line in ("MD5Sum:", "SHA1:", "SHA256:"):
        algorithm = {"MD5Sum:": "md5", "SHA1:": "sha1", "SHA256:": "sha256"}[line]
    elif line.startswith(" ") and algorithm:
        digest, size, name = line.split()
        if name in blobs:
            assert hashlib.new(algorithm, blobs[name]).hexdigest() == digest
            assert len(blobs[name]) == int(size)
            checked.add((algorithm, name))
assert len(checked) == 9, "Release must cover all three indexes with all three hashes"

entries = []
for stanza in index.decode().split("\n\n"):
    fields = dict(line.split(": ", 1) for line in stanza.splitlines()
                  if line and not line.startswith(" ") and ": " in line)
    if fields.get("Package") in EXPECTED:
        entries.append(fields)
assert len(entries) == len(EXPECTED), "missing or duplicate package entries"

for fields in entries:
    version, digest = EXPECTED[fields["Package"]]
    assert fields["Version"] == version
    assert fields["Architecture"] == "iphoneos-arm64"
    assert fields["SHA256"] == digest
    assert fields["Filename"].startswith("debs/")
    payload = fetch(fields["Filename"])
    assert len(payload) == int(fields["Size"])
    assert hashlib.sha256(payload).hexdigest() == digest
    print("PUBLIC_PACKAGE_PASS", fields["Package"], version, digest, flush=True)

print("PUBLIC_INDEX_PASS source, gzip, bzip2 and all Release hashes match", flush=True)
