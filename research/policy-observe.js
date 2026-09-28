const C=ObjC.classes;
const s=C.NEPolicySession.alloc().init();
const dump=s.dumpKernelPolicies().toString();
console.log(dump.split('\n').filter(l=>/IPTunnel|scoped-direct|Scoped|utun|privileged-tunnel/.test(l)).slice(0,65).join('\n'));
s.release();
