// Read-only selectors and export names; never print configurations or credentials.
console.log('ObjC available: '+(typeof ObjC!=='undefined' && ObjC.available));
if(typeof ObjC!=='undefined' && ObjC.available) {
  for(const name of ['NESMVPNSession','NESMIPTunnelSession','NESMPacketTunnelSession','NEVirtualInterface']) {
    const cls=ObjC.classes[name];if(!cls)continue;
    console.log('CLASS '+name);
    for(const method of cls.$ownMethods)if(/interface|metadata|uuid|perapp/i.test(method))console.log(method);
  }
}
for(const module of Process.enumerateModules())if(module.name==='NetworkExtension')
  for(const value of module.enumerateExports())if(value.name.includes('VirtualInterface'))console.log(value.name);
