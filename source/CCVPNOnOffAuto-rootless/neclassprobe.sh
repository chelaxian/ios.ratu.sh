#!/bin/bash
# Enumerate NetworkExtension ObjC classes + selectors to find the real
# connect/start method that Settings.app's VPN toggle uses (handles IPC
# internally, unlike the crashing raw ne_session_* C calls).
cat > /tmp/neclassprobe.m <<'OBJC'
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void dumpClass(NSString *cn) {
    Class c = NSClassFromString(cn);
    if (!c) { fprintf(stderr, "%-34s MISSING\n", cn.UTF8String); return; }
    fprintf(stderr, "===== %s =====\n", cn.UTF8String);
    unsigned int n = 0;
    Method *m = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++)
        fprintf(stderr, "  - %s\n", sel_getName(method_getName(m[i])));
    free(m);
    // class methods
    Class meta = object_getClass(c);
    Method *cm = class_copyMethodList(meta, &n);
    for (unsigned i = 0; i < n; i++)
        fprintf(stderr, "  + %s\n", sel_getName(method_getName(cm[i])));
    free(cm);
}

int main() {
    @autoreleasepool {
        // load framework
        dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
        NSArray *classes = @[
            @"NEConfigurationManager", @"NEConfiguration", @"NEVPN",
            @"NETunnelProviderManager", @"NEVPNManager", @"NEVPNConnection",
            @"NEConfigurationConnection", @"NEAppProxyProviderManager",
            @"NEHotspotHelper", @"NEFilterManager"
        ];
        for (NSString *c in classes) dumpClass(c);
        // list ALL classes whose name starts with NE
        fprintf(stderr, "\n===== ALL NE* classes =====\n");
        int num = objc_getClassList(NULL, 0);
        Class *all = (Class *)malloc(sizeof(Class) * num);
        objc_getClassList(all, num);
        for (int i = 0; i < num; i++) {
            const char *nm = class_getName(all[i]);
            if (strncmp(nm, "NE", 2) == 0) fprintf(stderr, "  %s\n", nm);
        }
        free(all);
    }
    return 0;
}
OBJC

CLANG=$(ls /var/jb/usr/bin/clang 2>/dev/null || which clang)
echo "compiler=$CLANG"
# RootHide provides clang; fall back to theos SDK if needed
SDK=$(ls -d /var/jb/usr/share/sysroot*/Developer/SDKs/* 2>/dev/null | head -1)
if [ -n "$SDK" ]; then ISYS="-isysroot $SDK"; fi
$CLANG $ISYS -fobjc-arc -framework Foundation -framework NetworkExtension \
  -lobjc -arch arm64 -o /tmp/neclassprobe /tmp/neclassprobe.m 2>&1 | head -20
echo "=== run ==="
/tmp/neclassprobe 2>&1 | sed 's/^.*+0000 //' | head -220
echo PROBE_DONE
