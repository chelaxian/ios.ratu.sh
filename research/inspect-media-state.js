// Read-only selectors and playback booleans, no media titles or user content.
ObjC.schedule(ObjC.mainQueue,()=>{
const lock=ObjC.classes.SBLockScreenManager;
if(lock&&lock['- _reallySetUILocked:'])console.log('LOCK_SETTER_ABI '+JSON.stringify({returns:lock['- _reallySetUILocked:'].returnType,args:lock['- _reallySetUILocked:'].argumentTypes}));
if(lock){console.log('LOCK_METHODS '+JSON.stringify(lock.$ownMethods.filter(s=>/locked|sharedInstance/i.test(s))));if(lock.respondsToSelector_(ObjC.selector('sharedInstanceIfExists'))){const instance=lock.sharedInstanceIfExists();if(instance)for(const name of ['isUILocked','isLocked'])if(instance.respondsToSelector_(ObjC.selector(name)))console.log('LOCK_BOOLEAN '+name+'='+instance[name]());}}
for(const name of ['SBMediaController','SBPictureInPictureController','PGPictureInPictureController']){
 const cls=ObjC.classes[name];if(!cls)continue;
 console.log('MEDIA_CLASS '+name+' '+JSON.stringify(cls.$ownMethods.filter(s=>/playing|playback|picture|active|shared/i.test(s))));
 if(name==='SBMediaController'&&cls.respondsToSelector_(ObjC.selector('sharedInstanceIfExists'))){const instance=cls.sharedInstanceIfExists();if(instance)for(const selector of ['isPlaying','isPaused'])if(instance.respondsToSelector_(ObjC.selector(selector)))console.log(selector+'='+instance[selector]());}
}
for(const module of Process.enumerateModules())if(module.name==='MediaRemote')for(const symbol of module.enumerateExports())if(/MRMediaRemoteGetNowPlayingApplicationIsPlaying/.test(symbol.name))console.log('MEDIA_EXPORT '+symbol.name);
});
