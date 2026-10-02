// Bounded prototype for the two explicitly authorized research configurations.
// No configuration data or credential values are inspected or printed.
const allowed=new Set(['E66EBF67-1B96-4D36-99A4-FE95DAC4D328','02414AFC-4D04-468C-A61C-42EFF2445475']);
const scope=new Map();
const parametersOwned=new Map();
const cls=ObjC.classes.NESMVPNSession;
const request=cls['- plugin:didRequestVirtualInterfaceWithParameters:completionHandler:'];
const observer=Interceptor.attach(request.implementation,{
  onEnter(args){
    this.tid=Process.getCurrentThreadId();
    try {
      const session=new ObjC.Object(args[0]);
      if(!session.respondsToSelector_(ObjC.selector('configuration')))return;
      const configuration=session.configuration();const id=configuration.identifier().UUIDString().toString();
      if(allowed.has(id)&&configuration.appVPN()){scope.set(this.tid,id);this.owned=true;console.log('OWNED_INTERFACE_REQUEST '+id);const parameters=new ObjC.Object(args[3]);parametersOwned.set(args[3].toString(),id);const socket=parameters.controlSocket();console.log('CONTROL_SOCKET_PRESENT '+!!socket);}
    }catch(error){console.log('SCOPE_ERROR '+error);}
  },
  onLeave(){if(this.owned)scope.delete(this.tid);}
});
const libc=Process.getModuleByName('libsystem_kernel.dylib');
const getSocketOption=new NativeFunction(libc.getExportByName('getsockopt'),'int',['int','int','int','pointer','pointer']);
const xpc=Process.getModuleByName('libxpc.dylib');
const getString=new NativeFunction(xpc.getExportByName('xpc_dictionary_get_string'),'pointer',['pointer','pointer']);
const controlName=Memory.allocUtf8String('socket-control-name');
const getValue=new NativeFunction(xpc.getExportByName('xpc_dictionary_get_value'),'pointer',['pointer','pointer']);
const arrayApply=new NativeFunction(xpc.getExportByName('xpc_array_apply'),'bool',['pointer','pointer']);
const getUint=new NativeFunction(xpc.getExportByName('xpc_dictionary_get_uint64'),'uint64',['pointer','pointer']);
const getData=new NativeFunction(xpc.getExportByName('xpc_dictionary_get_data'),'pointer',['pointer','pointer','pointer']);
const setData=new NativeFunction(xpc.getExportByName('xpc_dictionary_set_data'),'void',['pointer','pointer','pointer','uint64']);
const optionsKey=Memory.allocUtf8String('socket-options'),optionKey=Memory.allocUtf8String('interface-option'),dataKey=Memory.allocUtf8String('interface-option-data');
const sends=[];
for(const name of ['xpc_connection_send_message','xpc_connection_send_message_with_reply','xpc_connection_send_message_with_reply_sync']) {
 const address=xpc.findExportByName(name);if(!address)continue;
 sends.push(Interceptor.attach(address,{onEnter(args){
   try {
    const value=getString(args[1],controlName),id=scope.get(Process.getCurrentThreadId());
    if(value.isNull()||value.readUtf8String()!=='com.apple.net.utun_control')return;
    console.log('UTUN_REQUEST_SEND '+JSON.stringify({owned:id||null,method:name}));
    if(!id||name!=='xpc_connection_send_message_with_reply_sync')return;
    this.restore=[];
    const options=getValue(args[1],optionsKey);if(options.isNull())return;
    const block=new ObjC.Block({retType:'bool',argTypes:['uint64','pointer'],implementation:(index,option)=>{
      if(getUint(option,optionKey).toString()!=='1')return true;
      const length=Memory.alloc(Process.pointerSize);length.writeU64(0);
      const data=getData(option,dataKey,length);if(data.isNull()||length.readU64().toString()!=='4')return true;
      const flags=data.readU32();if(!(flags&4))return true;
      const original=Memory.alloc(4);original.writeU32(flags);this.restore.push({option,original});
      const compatible=Memory.alloc(4);compatible.writeU32(flags&~4);setData(option,dataKey,compatible,4);
      console.log('OWNED_FRAMING_REQUEST '+JSON.stringify({id,before:flags,after:flags&~4}));return true;
    }});arrayApply(options,block.handle);
   }catch(error){console.log('REQUEST_INSPECT_ERROR '+error);}
 },onLeave(){for(const entry of this.restore||[])setData(entry.option,dataKey,entry.original,4);}}));
}
const creator=Interceptor.attach(ObjC.classes.NEVirtualInterfaceParameters['- createVirtualInterfaceWithQueue:clientInfo:'].implementation,{
  onEnter(args){this.tid=Process.getCurrentThreadId();this.id=parametersOwned.get(args[0].toString());if(this.id){scope.set(this.tid,this.id);console.log('OWNED_CREATE_INTERFACE '+this.id);}},
  onLeave(){if(this.id)scope.delete(this.tid);}
});
const setter=Interceptor.attach(libc.getExportByName('setsockopt'),{
  onEnter(args){
    if(args[1].toInt32()!==2 || args[2].toInt32()!==1 || args[4].toInt32()!==4)return;
    const id=scope.get(Process.getCurrentThreadId());
    console.log('UTUN_FLAGS_SET '+JSON.stringify({id:id||null,flags:args[3].readU32(),stack:Thread.backtrace(this.context,Backtracer.ACCURATE).slice(0,10).map(DebugSymbol.fromAddress).map(String)}));
    if(id&&(args[3].readU32()&4)){
      this.fd=args[0].toInt32();
      this.flags=Memory.alloc(4);this.flags.writeU32(args[3].readU32()&~4);args[3]=this.flags;this.changed=true;
      console.log('OWNED_LOCAL_FLAGS_CLEAR '+id);
    }
  },
  onLeave(result){if(this.changed){
    // The kernel rejects setting FLAGS after connect, even if the requested
    // value is already installed. Treat only this verified no-op as success.
    if(result.toInt32()!==0){const value=Memory.alloc(4),length=Memory.alloc(4);length.writeU32(4);
      if(getSocketOption(this.fd,2,1,value,length)===0 && length.readU32()===4 && value.readU32()===this.flags.readU32()){
        result.replace(0);console.log('OWNED_FLAGS_ALREADY_MATCH');
      }
    }
    console.log('OWNED_FLAGS_RESULT '+result.toInt32());
  }}
});
setTimeout(()=>{for(const send of sends)send.detach();setter.detach();creator.detach();observer.detach();scope.clear();parametersOwned.clear();console.log('FRAMING_PROBE_DETACHED');},90000);
console.log('SCOPED_FRAMING_PROBE_READY');
