"""Inspect actual rootless payload, current arm64e ABI and signed page hashes."""
import hashlib
import io
import pathlib
import struct
import sys
import tarfile


def ar_members(raw):
    assert raw[:8] == b"!<arch>\n"
    at, result = 8, {}
    while at < len(raw):
        header = raw[at:at + 60]
        size = int(header[48:58])
        result[header[:16].decode().strip().rstrip("/")] = raw[at + 60:at + 60 + size]
        at += 60 + size + size % 2
    return result


def mach_slices(raw):
    assert raw[:4] == b"\xca\xfe\xba\xbe", "Expected universal Mach-O"
    count = struct.unpack_from(">I", raw, 4)[0]
    for index in range(count):
        cpu, subtype, at, size, _ = struct.unpack_from(">IIIII", raw, 8 + index * 20)
        blob = raw[at:at + size]
        assert blob[:4] == b"\xcf\xfa\xed\xfe"
        assert struct.unpack_from("<II", blob, 4) == (cpu, subtype)
        yield subtype, blob


def verify_signature(blob, offset, size):
    signature = blob[offset:offset + size]
    magic, length, count = struct.unpack_from(">III", signature)
    assert magic == 0xFADE0CC0 and length <= size
    directories = 0
    for index in range(count):
        _, start = struct.unpack_from(">II", signature, 12 + index * 8)
        submagic, sublength = struct.unpack_from(">II", signature, start)
        assert start + sublength <= length
        if submagic != 0xFADE0C02:
            continue
        directory = signature[start:start + sublength]
        hash_offset, _, _, pages, code_limit = struct.unpack_from(">IIIII", directory, 16)
        hash_size, hash_type, _, page_power = struct.unpack_from("4B", directory, 36)
        digest = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256, 4: hashlib.sha384}[hash_type]
        page_size = 1 << page_power
        assert code_limit <= offset and pages == (code_limit + page_size - 1) // page_size
        for page in range(pages):
            expected = directory[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
            actual = digest(blob[page * page_size:min((page + 1) * page_size, code_limit)]).digest()[:hash_size]
            assert actual == expected, "Invalid signed code page"
        directories += 1
    assert directories, "No CodeDirectory"


def inspect(path):
    entries = ar_members(path.read_bytes())
    control_tar = tarfile.open(fileobj=io.BytesIO(next(v for k, v in entries.items() if k.startswith("control.tar"))))
    control = control_tar.extractfile(next(m for m in control_tar if m.name.rstrip("/").endswith("control"))).read().decode()
    assert "Architecture: iphoneos-arm64\n" in control
    assert "Package: com.level3tjg.offloader\n" in control
    assert "Version: 1.0.0\n" in control
    for obsolete in ("libmryipc", "altlist", "roothide"):
        assert obsolete not in control.lower()
    print(control.strip())
    payload = tarfile.open(fileobj=io.BytesIO(next(v for k, v in entries.items() if k.startswith("data.tar"))))
    binaries = 0
    for member in payload:
        if not member.isfile():
            continue
        name = member.name.lstrip("./")
        assert name.startswith("var/jb/"), name
        raw = payload.extractfile(member).read()
        if not (name.endswith(".dylib") or name.endswith("OffloaderPrefs.bundle/OffloaderPrefs")):
            continue
        binaries += 1
        assert all(term not in raw for term in (b"/rootfs", b"libroothide", b"libmryipc", b"AltList.framework"))
        slices = list(mach_slices(raw))
        assert {sub for sub, _ in slices} == {0, 0x80000002}, "Wrong arm64e ABI"
        for subtype, blob in slices:
            at, signature = 32, None
            commands = struct.unpack_from("<I", blob, 16)[0]
            for _ in range(commands):
                command, length = struct.unpack_from("<II", blob, at)
                assert length >= 8 and at + length <= len(blob)
                if command == 0x1D:
                    signature = struct.unpack_from("<II", blob, at + 8)
                at += length
            assert signature and signature[1] > 0
            verify_signature(blob, *signature)
            print(name, hex(subtype), "signed code page hashes PASS")
    assert binaries == 3
    print("PASS: rootless layout, metadata, three universal binaries, PTRAUTH ABI and signed code page hashes")


if __name__ == "__main__":
    inspect(pathlib.Path(sys.argv[1]))
