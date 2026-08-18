#!/usr/bin/env python3
# Enumerate NetworkExtension ObjC classes via libobjc (ctypes) — no compiler.
import ctypes
objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')

objc.objc_getClass.restype = ctypes.c_void_p
objc.objc_getClass.argtypes = [ctypes.c_char_p]
objc.class_getName.restype = ctypes.c_char_p
objc.class_getName.argtypes = [ctypes.c_void_p]
objc.object_getClass.restype = ctypes.c_void_p
objc.object_getClass.argtypes = [ctypes.c_void_p]

Method_p = ctypes.POINTER(ctypes.c_void_p)
objc.class_copyMethodList.restype = Method_p
objc.class_copyMethodList.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint)]
objc.method_getName.restype = ctypes.c_void_p
objc.method_getName.argtypes = [ctypes.c_void_p]
objc.sel_getName.restype = ctypes.c_char_p
objc.sel_getName.argtypes = [ctypes.c_void_p]
objc.objc_getClassList.restype = ctypes.c_int
objc.objc_getClassList.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int]

libc = ctypes.CDLL('/usr/lib/libSystem.dylib')
libc.dlopen.restype = ctypes.c_void_p
libc.dlopen.argtypes = [ctypes.c_char_p, ctypes.c_int]
libc.dlopen(b'/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension', 2)

def methods(cls):
    n = ctypes.c_uint(0)
    m = objc.class_copyMethodList(cls, ctypes.byref(n))
    out = []
    for i in range(n.value):
        out.append(objc.sel_getName(objc.method_getName(m[i])).decode())
    return out

def dump(name):
    cls = objc.objc_getClass(name.encode())
    if not cls:
        print("%-32s MISSING" % name); return
    print("===== %s =====" % name)
    for s in sorted(set(methods(cls))):
        print("  - %s" % s)
    meta = objc.object_getClass(cls)
    for s in sorted(set(methods(meta))):
        print("  + %s" % s)

for c in ["NEConfigurationManager","NEConfiguration","NEVPN",
          "NETunnelProviderManager","NEVPNManager","NEVPNConnection",
          "NEConfigurationConnection","NEAppProxyProviderManager","NEFilterManager"]:
    dump(c)

print("\n===== ALL NE*/VPN/Tunnel/Session classes =====")
num = objc.objc_getClassList(None, 0)
buf = (ctypes.c_void_p * num)()
objc.objc_getClassList(buf, num)
for i in range(num):
    cls = buf[i]
    nm = objc.class_getName(cls).decode()
    if nm.startswith("NE") or "VPN" in nm or "Tunnel" in nm or "Session" in nm:
        print("  %s" % nm)
print("PROBE_DONE")
