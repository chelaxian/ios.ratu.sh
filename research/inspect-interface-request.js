// Read-only observation of interface construction. Never dump a VPN configuration.
const cls=ObjC.classes.NESMVPNSession;
const method=cls['- plugin:didRequestVirtualInterfaceWithParameters:completionHandler:'];
Interceptor.attach(method.implementation,{onEnter(args){
  try {
    const parameters=new ObjC.Object(args[3]);console.log('PARAMETERS_CLASS '+parameters.$className);
    if(parameters.$className==='NEVirtualInterfaceParameters')console.log('INTERFACE_TYPE='+parameters.type());
    if(parameters.$className.includes('Dictionary')) {
      const keys=parameters.allKeys();for(let i=0;i<keys.count();i++) {
        const key=keys.objectAtIndex_(i);const value=parameters.objectForKey_(key);
        console.log('PARAMETER '+key.toString()+' class='+value.$className);
        if(value.isKindOfClass_(ObjC.classes.NSNumber))console.log('NUMBER '+key.toString()+'='+value.toString());
      }
    }else for(const name of parameters.$ownMethods)if(/uuid|metadata|flag|type|enable|init/i.test(name))console.log('PARAMETER_METHOD '+name);
  }catch(error){console.log('INSPECT_ERROR '+error);}
}});
console.log('INTERFACE_REQUEST_OBSERVER_READY');
