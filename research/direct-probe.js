const C=ObjC.classes;
const session=C.NEPolicySession.alloc().init();
session.setPriority_(1);
const ids=C.NEProcessInfo.copyUUIDsForExecutable_('/var/jb/usr/bin/curl');
console.log('curl UUIDs '+ids);
for(let i=0;i<ids.count();i++) {
 const cond=C.NEPolicyCondition.effectiveApplication_(ids.objectAtIndex_(i));
 const result=C.NEPolicyResult.scopeToDirectInterface();
 const cs=C.NSMutableArray.array(); cs.addObject_(cond); cs.addObject_(C.NEPolicyCondition.allInterfaces());
 const policy=C.NEPolicy.alloc().initWithOrder_result_conditions_(100,result,cs);
 console.log('add '+session.addPolicy_(policy)+' '+policy);
}
console.log('apply '+session.apply());
setTimeout(()=>{session.removeAllPolicies(); console.log('cleanup '+session.apply());session.release();},50000);
