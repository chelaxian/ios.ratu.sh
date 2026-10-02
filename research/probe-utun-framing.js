// Bounded research only. Keep all flags except the 16-byte process-UUID header.
// Restore every changed socket after 60 s; the enclosing test also closes its tunnels.
const libc=Process.getModuleByName('libsystem_kernel.dylib');
const getOption=new NativeFunction(libc.getExportByName('getsockopt'),'int',['int','int','int','pointer','pointer']);
const setOption=new NativeFunction(libc.getExportByName('setsockopt'),'int',['int','int','int','pointer','uint']);
const changes=[];
for(let fd=0;fd<512;fd++) {
  const name=Memory.alloc(64),length=Memory.alloc(4);length.writeU32(64);
  if(getOption(fd,2,2,name,length)!==0 || length.readU32()<5 || name.readU8()!==117 || name.add(1).readU8()!==116)continue;
  const interfaceName=name.readUtf8String();if(!interfaceName.startsWith('utun'))continue;
  const flags=Memory.alloc(4);length.writeU32(4);if(getOption(fd,2,1,flags,length)!==0)continue;
  const old=flags.readU32();if(!(old&4))continue;flags.writeU32(old&~4);
  const result=setOption(fd,2,1,flags,4);console.log(JSON.stringify({fd,interface:interfaceName,before:old,after:old&~4,result}));
  if(result===0)changes.push({fd,old,interfaceName});
}
setTimeout(()=>{
  for(const change of changes){const flags=Memory.alloc(4);flags.writeU32(change.old);const name=Memory.alloc(64),length=Memory.alloc(4);length.writeU32(64);
    if(getOption(change.fd,2,2,name,length)===0 && name.readU8()===117 && name.readUtf8String()===change.interfaceName)
      console.log(JSON.stringify({restore:change.interfaceName,result:setOption(change.fd,2,1,flags,4)}));
  }
},60000);
