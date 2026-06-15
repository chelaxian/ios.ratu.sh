import fs from "node:fs";

const [input, output, dylibPath] = process.argv.slice(2);
if (!input || !output || !dylibPath) {
  throw new Error("usage: node insert-load-dylib.mjs input output dylib-path");
}

const data = fs.readFileSync(input);
if (data.readUInt32LE(0) !== 0xfeedfacf) {
  throw new Error("expected a thin little-endian Mach-O 64 binary");
}
if (data.includes(Buffer.from(`${dylibPath}\0`))) {
  fs.writeFileSync(output, data);
  process.exit(0);
}

const headerSize = 32;
const commandCount = data.readUInt32LE(16);
const commandsSize = data.readUInt32LE(20);
let cursor = headerSize;
let firstSectionOffset = data.length;

for (let index = 0; index < commandCount; index++) {
  const command = data.readUInt32LE(cursor);
  const commandSize = data.readUInt32LE(cursor + 4);
  if (commandSize < 8 || cursor + commandSize > data.length) {
    throw new Error("invalid Mach-O load command table");
  }

  if (command === 0x19) {
    const sectionCount = data.readUInt32LE(cursor + 64);
    for (let section = 0; section < sectionCount; section++) {
      const sectionOffset = data.readUInt32LE(cursor + 72 + section * 80 + 48);
      if (sectionOffset > 0) {
        firstSectionOffset = Math.min(firstSectionOffset, sectionOffset);
      }
    }
  }
  cursor += commandSize;
}

const pathBytes = Buffer.from(`${dylibPath}\0`);
const newCommandSize = (24 + pathBytes.length + 7) & ~7;
const insertOffset = headerSize + commandsSize;
if (insertOffset + newCommandSize > firstSectionOffset) {
  throw new Error("not enough Mach-O load-command padding");
}

data.fill(0, insertOffset, insertOffset + newCommandSize);
data.writeUInt32LE(0x0c, insertOffset);
data.writeUInt32LE(newCommandSize, insertOffset + 4);
data.writeUInt32LE(24, insertOffset + 8);
data.writeUInt32LE(2, insertOffset + 12);
data.writeUInt32LE(0, insertOffset + 16);
data.writeUInt32LE(0, insertOffset + 20);
pathBytes.copy(data, insertOffset + 24);
data.writeUInt32LE(commandCount + 1, 16);
data.writeUInt32LE(commandsSize + newCommandSize, 20);

fs.writeFileSync(output, data);
