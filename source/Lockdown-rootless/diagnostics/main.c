#include <JavaScriptCore/JavaScriptCore.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    const char *jscPath = "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore";
    void *jsc = dlopen(jscPath, RTLD_NOW);
    void *ek = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
    if (!jsc || !ek) { puts("FAIL: JSC/ElleKit load"); return 1; }
    void *(*getImage)(const char *) = dlsym(ek, "MSGetImageByName");
    void *(*findSymbol)(void *, const char *) = dlsym(ek, "MSFindSymbol");
    if (!getImage || !findSymbol) { puts("FAIL: Substrate symbol resolver unavailable"); return 1; }
    void *image = getImage(jscPath);
    const char *symbols[] = {
        "__ZN3JSC7Options10initializeEv",
        "__ZN3JSC7Options9setOptionEPKc",
        "__ZN3JSC7Options9setOptionEPKcb",
        "__ZN3JSC7Options20notifyOptionsChangedEv",
        "__ZN3JSC14JSGlobalObject4initERNS_2VME",
        "__ZN3JSC14JSGlobalObject12haveABadTimeERNS_2VME"
    };
    int found[6] = {0};
    for (int i = 0; i < 6; i++) {
        found[i] = findSymbol(image, symbols[i]) != NULL;
        printf("%s %s\n", found[i] ? "FOUND" : "ABSENT", symbols[i]);
    }
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    JSStringRef source = JSStringCreateWithUTF8CString(
        "(()=>{let a=[1.5,2.5,3.5]; let o={x:7}; const t=new Uint32Array([3,5,9]);"
        "return a.reduce((x,y)=>x+y,0)+o.x+t[2]})()");
    JSValueRef exception = NULL;
    JSValueRef result = JSEvaluateScript(ctx, source, NULL, NULL, 1, &exception);
    int ok = result && !exception && JSValueToNumber(ctx, result, NULL) == 23.5;
    printf("%s baseline JavaScript arrays/objects/typed-array execution\n", ok ? "PASS" : "FAIL");
    JSStringRelease(source);
    JSGlobalContextRelease(ctx);
    int compatible = found[0] && (found[1] || found[2]) && found[4] && found[5];
    puts("NOTE: standalone arm64 symbol/API probe; no platform injection or hardening proof");
    return ok && compatible ? 0 : 2;
}
