const C=ObjC.classes;
for(const n of ['LSApplicationProxy','LSPlugInKitProxy'])console.log(n+' '+(C[n]?C[n].$ownMethods.filter(x=>/bundle|containing|plugin/i.test(x)).join(','):'missing'));
const app=C.LSApplicationProxy.applicationProxyForIdentifier_('com.apple.mobilesafari');
console.log('bundleURL='+app.bundleURL());console.log('plugins='+app.plugInKitPlugins().count());
console.log('UUIDs='+C.NEProcessInfo.copyUUIDsForBundleID_uid_('com.apple.mobilesafari',501));
