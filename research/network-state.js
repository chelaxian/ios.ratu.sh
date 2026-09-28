const sc=Process.getModuleByName('SystemConfiguration');
const copy=new NativeFunction(sc.getExportByName('SCDynamicStoreCopyMultiple'),'pointer',['pointer','pointer','pointer']);
const patterns=ObjC.classes.NSArray.arrayWithObject_('State:/Network/Service/.*/IPv[46]');
const p=copy(ptr(0),ptr(0),patterns.handle);
if(!p.isNull()) {
 const dict=new ObjC.Object(p),keys=dict.allKeys();
 for(let i=0;i<keys.count();i++) {
  const key=keys.objectAtIndex_(i),value=dict.objectForKey_(key);
  const iface=value.objectForKey_('InterfaceName');
  console.log(key.toString()+' interface='+iface);
 }
 dict.release();
}
