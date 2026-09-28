const C=ObjC.classes;
const session=C.NEPolicySession.alloc().init(); session.setPriority_(1);
const ids=C.NEProcessInfo.copyUUIDsForExecutable_('/var/jb/usr/bin/curl');
for(let i=0;i<ids.count();i++) {
 const cs=C.NSMutableArray.array();
 cs.addObject_(C.NEPolicyCondition.effectiveApplication_(ids.objectAtIndex_(i)));
 cs.addObject_(C.NEPolicyCondition.allInterfaces());
 const p=C.NEPolicy.alloc().initWithOrder_result_conditions_(100,C.NEPolicyResult.skipWithOrder_(0),cs);
 console.log('VPN exception '+session.addPolicy_(p));
}
const p=C.NEPolicy.alloc().initWithOrder_result_conditions_(1000,C.NEPolicyResult.scopeToDirectInterface(),C.NSArray.arrayWithObject_(C.NEPolicyCondition.allInterfaces()));
console.log('DIRECT default '+session.addPolicy_(p));console.log('apply '+session.apply());
setTimeout(()=>{session.removeAllPolicies();console.log('cleanup '+session.apply());session.release();},40000);
