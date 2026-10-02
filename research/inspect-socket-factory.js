// Read-only XPC schema inspection: names and types only, no values or descriptions.
const listeners=[];
const xpc=Process.getModuleByName('libxpc.dylib');
const apply=new NativeFunction(xpc.getExportByName('xpc_dictionary_apply'),'bool',['pointer','pointer']);
const getType=new NativeFunction(xpc.getExportByName('xpc_get_type'),'pointer',['pointer']);
const typeName=new NativeFunction(xpc.getExportByName('xpc_type_get_name'),'pointer',['pointer']);
const remote=new NativeFunction(xpc.getExportByName('xpc_dictionary_get_remote_connection'),'pointer',['pointer']);
const pid=new NativeFunction(xpc.getExportByName('xpc_connection_get_pid'),'int',['pointer']);
const arrayApply=new NativeFunction(xpc.getExportByName('xpc_array_apply'),'bool',['pointer','pointer']);
const getInt=new NativeFunction(xpc.getExportByName('xpc_int64_get_value'),'int64',['pointer']);
const getUint=new NativeFunction(xpc.getExportByName('xpc_uint64_get_value'),'uint64',['pointer']);
const cls=ObjC.classes.NEHelperSocketFactory;
console.log('SOCKET_FACTORY_METHODS '+JSON.stringify(cls.$ownMethods));
listeners.push(Interceptor.attach(cls['- handleMessage:'].implementation,{onEnter(args){
  const connection=remote(args[2]);console.log('FACTORY_PEER_PID '+(connection.isNull()?0:pid(connection)));
  console.log('FACTORY_IVARS '+JSON.stringify(Object.keys(new ObjC.Object(args[0]).$ivars)));
  let count=0;
  const callback=new ObjC.Block({retType:'bool',argTypes:['pointer','pointer'],implementation:(key,value)=>{
    const name=key.readUtf8String(),type=typeName(getType(value)).readUtf8String();
    if(++count<=40)console.log('XPC_FIELD '+name+' type='+type);
    if(name==='socket-options'&&type==='array'){
      const optionBlock=new ObjC.Block({retType:'bool',argTypes:['uint64','pointer'],implementation:(index,option)=>{
        const optionType=typeName(getType(option)).readUtf8String();console.log('OPTION_TYPE '+optionType);
        if(optionType==='dictionary'){
          const fields=new ObjC.Block({retType:'bool',argTypes:['pointer','pointer'],implementation:(key,item)=>{
            const type=typeName(getType(item)).readUtf8String();let suffix='';
            if(type==='uint64')suffix=' integer='+getUint(item);
            if(type==='int64')suffix=' integer='+getInt(item);
            console.log('OPTION_FIELD '+key.readUtf8String()+' type='+type+suffix);return true;
          }});apply(option,fields.handle);
        }return true;
      }});arrayApply(value,optionBlock.handle);
    }
    return true;
  }});
  apply(args[2],callback.handle);
}}));
setTimeout(()=>{for(const listener of listeners)listener.detach();console.log('SOCKET_FACTORY_INSPECTION_DETACHED');},90000);
