// Read-only engine diagnostics for the explicitly authorized WireGuard extension.
// No raw runtime configuration, peer keys, private keys or pre-shared keys printed.
const bundle=ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString();
if(bundle!=='com.wireguard.ios.network-extension')throw new Error('REFUSED_OTHER_PROVIDER');
let getAddress=null;
for(const module of Process.enumerateModules()){getAddress=module.findExportByName('wgGetConfig');if(getAddress)break;}
if(!getAddress){console.log('WG_RUNTIME_EXPORT_UNAVAILABLE');}
else{
 const get=new NativeFunction(getAddress,'pointer',['int']);
 const free=new NativeFunction(Process.getModuleByName('libsystem_malloc.dylib').getExportByName('free'),'void',['pointer']);
 let found=0;
 for(let handle=0;handle<4;handle++){
   const value=get(handle);if(value.isNull())continue;found++;
   try{
     const text=value.readUtf8String();
     for(const line of text.split('\n')){
       const match=/^(endpoint|rx_bytes|tx_bytes|last_handshake_time_sec)=([A-Za-z0-9.:\[\]-]{1,255})$/.exec(line);
       if(match)console.log('WG_ENGINE '+JSON.stringify({handle,key:match[1],value:match[2]}));
     }
   }finally{free(value);}
 }
 console.log('WG_ACTIVE_HANDLES '+found);
}
