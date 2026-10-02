// Read-only: inspect the utun sockets owned by the attached VPN extension.
const libc = Process.getModuleByName('libsystem_kernel.dylib');
const getOption = new NativeFunction(libc.getExportByName('getsockopt'), 'int', ['int','int','int','pointer','pointer']);
for(let fd=0;fd<512;fd++) {
  const name=Memory.alloc(64), length=Memory.alloc(4);length.writeU32(64);
  if(getOption(fd,2,2,name,length)!==0)continue;
  if(length.readU32()<5 || name.readU8()!==117 || name.add(1).readU8()!==116)continue;
  const interfaceName=name.readUtf8String();if(!interfaceName || !interfaceName.startsWith('utun'))continue;
  const flags=Memory.alloc(4);length.writeU32(4);
  if(getOption(fd,2,1,flags,length)===0)console.log(JSON.stringify({fd,interface:interfaceName,flags:flags.readU32(),procUUID:!!(flags.readU32()&4)}));
}
