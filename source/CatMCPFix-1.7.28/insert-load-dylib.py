#!/usr/bin/env python3
import struct
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: insert-load-dylib.py input output dylib-path")

input_path, output_path, dylib_path = sys.argv[1:]
data = bytearray(open(input_path, "rb").read())
if struct.unpack_from("<I", data, 0)[0] != 0xfeedfacf:
    raise SystemExit("expected a thin little-endian Mach-O 64 binary")

needle = (dylib_path + "\0").encode()
if needle in data:
    open(output_path, "wb").write(data)
    raise SystemExit(0)

header_size = 32
command_count = struct.unpack_from("<I", data, 16)[0]
commands_size = struct.unpack_from("<I", data, 20)[0]
cursor = header_size
first_section_offset = len(data)

for _ in range(command_count):
    command, command_size = struct.unpack_from("<II", data, cursor)
    if command_size < 8 or cursor + command_size > len(data):
        raise SystemExit("invalid Mach-O load command table")
    if command == 0x19:
        section_count = struct.unpack_from("<I", data, cursor + 64)[0]
        for section in range(section_count):
            section_offset = struct.unpack_from("<I", data, cursor + 72 + section * 80 + 48)[0]
            if section_offset:
                first_section_offset = min(first_section_offset, section_offset)
    cursor += command_size

new_command_size = (24 + len(needle) + 7) & ~7
insert_offset = header_size + commands_size
if insert_offset + new_command_size > first_section_offset:
    raise SystemExit("not enough Mach-O load-command padding")

data[insert_offset:insert_offset + new_command_size] = b"\0" * new_command_size
struct.pack_into("<IIIIII", data, insert_offset, 0x0c, new_command_size, 24, 2, 0, 0)
data[insert_offset + 24:insert_offset + 24 + len(needle)] = needle
struct.pack_into("<I", data, 16, command_count + 1)
struct.pack_into("<I", data, 20, commands_size + new_command_size)
open(output_path, "wb").write(data)
