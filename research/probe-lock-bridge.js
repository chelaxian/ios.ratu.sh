// Bounded observation: publishes only the new tweak-owned notification.
// Does not change the lock screen, VPN, playback, or existing system notifications.
const lib=Process.getModuleByName('libsystem_notify.dylib');
const register=new NativeFunction(lib.getExportByName('notify_register_check'),'uint',['pointer','pointer']);
const set=new NativeFunction(lib.getExportByName('notify_set_state'),'uint',['int','uint64']);
const post=new NativeFunction(lib.getExportByName('notify_post'),'uint',['pointer']);
const cancel=new NativeFunction(lib.getExportByName('notify_cancel'),'uint',['int']);
const name=Memory.allocUtf8String('com.ratush.appsplitvpn.ui-lock');
const tokenStorage=Memory.alloc(4);let token=-1;
const cls=ObjC.classes.SBLockScreenManager;
function publish(manager){if(token<0)return;const locked=!!manager.isUILocked();const result=set(token,locked?3:2);if(result===0)post(name);console.log('BRIDGE_STATE '+JSON.stringify({locked,result}));}
if(register(name,tokenStorage)===0)token=tokenStorage.readS32();
const observer=Interceptor.attach(cls['- _reallySetUILocked:'].implementation,{onEnter(args){this.manager=new ObjC.Object(args[0]);},onLeave(){const manager=this.manager;ObjC.schedule(ObjC.mainQueue,()=>publish(manager));}});
ObjC.schedule(ObjC.mainQueue,()=>{const instance=cls.sharedInstanceIfExists();if(instance)publish(instance);});
setTimeout(()=>{observer.detach();if(token>=0)cancel(token);token=-1;console.log('LOCK_BRIDGE_PROBE_DETACHED');},60000);
