"""Validate the extracted final DEB; run after dpkg-deb -x and -e."""
import plistlib
import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
control = (root / 'DEBIAN/control').read_text()
assert 'Architecture: iphoneos-arm64\n' in control
assert 'Package: com.ratush.lockdown\n' in control
assert 'Depends: ellekit, firmware (>= 17.0), firmware (<< 17.1)' in control
assert 'roothide' not in control.split('Depends:')[1].splitlines()[0]
payload = [p for p in root.rglob('*') if p.is_file() and 'DEBIAN' not in p.relative_to(root).parts]
assert len(payload) == 2, payload
assert all(p.relative_to(root).as_posix().startswith('var/jb/') for p in payload)
plist = next(p for p in payload if p.suffix == '.plist')
assert plistlib.loads(plist.read_bytes()) == {'Filter': {'Executables': ['com.apple.WebKit.WebContent']}}
binary = next(p for p in payload if p.suffix == '.dylib')
assert binary.name == 'lockdown2.dylib'
b = binary.read_bytes()
assert b[:4] == b'\xca\xfe\xba\xbe', 'Expected universal Mach-O'
count = struct.unpack_from('>I', b, 4)[0]
assert count == 2
subtypes = set()
for i in range(count):
    cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', b, 8 + i * 20)
    assert cpu == 0x0100000C
    header = struct.unpack_from('<8I', b, offset)
    assert header[0] == 0xFEEDFACF
    assert header[1:3] == (cpu, subtype)
    subtypes.add(subtype)
    cursor = offset + 32
    signed = False
    for _ in range(header[4]):
        cmd, cmdsize = struct.unpack_from('<II', b, cursor)
        assert cmdsize >= 8 and cursor + cmdsize <= offset + size
        if cmd == 0x1D:
            dataoff, datasize = struct.unpack_from('<II', b, cursor + 8)
            assert datasize > 0 and dataoff + datasize <= size
            assert b[offset + dataoff:offset + dataoff + 4] == b'\xfa\xde\x0c\xc0'
            signed = True
        if cmd in (0xC, 0x80000018, 0x8000001F):
            nameoff = struct.unpack_from('<I', b, cursor + 8)[0]
            name = b[cursor + nameoff:cursor + cmdsize].split(b'\0', 1)[0].decode()
            assert 'roothide' not in name.lower(), name
            assert not name.startswith('/Library/'), name
            if 'substrate' in name.lower():
                assert name.startswith(('/var/jb/', '@rpath/')), name
            print('library:', name)
        cursor += cmdsize
    assert signed, 'Unsigned slice'
    print(f'Mach-O slice: cpu=0x{cpu:x}, subtype=0x{subtype:08x}, signature=present')
assert subtypes == {0, 0x80000002}, f'Wrong ABI: {subtypes}'
for name in ('postinst', 'postrm'):
    script = root / 'DEBIAN' / name
    assert script.read_bytes().startswith(b'#!/bin/sh\n')
    assert script.stat().st_mode & 0o111
print('PASS: metadata, rootless layout, narrow filter, both slices, arm64e PAC ABI, signatures, scripts')
