// Read-only and bounded. Prints socket flags and symbol names, never profile data.
const listeners=[];
const kernel=Process.getModuleByName('libsystem_kernel.dylib');
const addresses=new Set();
for(const symbol of kernel.enumerateExports())if(/setsockopt/.test(symbol.name)&&!addresses.has(symbol.address.toString())){
  addresses.add(symbol.address.toString());
  listeners.push(Interceptor.attach(symbol.address,{onEnter(args){
    if(args[1].toInt32()!==2||args[2].toInt32()!==1||args[4].toInt32()!==4)return;
    console.log('FLAGS '+JSON.stringify({symbol:symbol.name,flags:args[3].readU32(),stack:Thread.backtrace(this.context,Backtracer.ACCURATE).slice(0,12).map(DebugSymbol.fromAddress).map(String)}));
  }}));
}
const ne=Process.findModuleByName('NetworkExtension');
if(ne)for(const name of ['NEVirtualInterfaceCreateWithOptions','NEVirtualInterfaceCreate','NEVirtualInterfaceCreateFromSocket']){
  const address=ne.findExportByName(name);if(!address)continue;
  listeners.push(Interceptor.attach(address,{onEnter(){console.log('CREATE '+name);}}));
}
console.log('READONLY_CREATION_OBSERVER_READY pid='+Process.id);
setTimeout(()=>{for(const listener of listeners)listener.detach();console.log('CREATION_OBSERVER_DETACHED');},90000);
