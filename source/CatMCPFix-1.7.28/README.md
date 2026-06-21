# CatMCP Fix 1.7.28

Companion package for CatMCP 1.0.3. It keeps the original server package
separate and provides autonomous lifecycle management plus reliable HID touch
delivery for standard rootless and RootHide Bootstrap installations.

The CatMCP bridge hooks the server's exported C++ touch entry points and sends
ordered Darwin-notify events to the SpringBoard bridge. This bypasses the
vendor IPC path that can block the serial HTTP listener after repeated touch
operations. `catmcp-autoinjectd` starts the enabled server when absent, injects
the bridge into the actual listener PID, performs conservative health checks,
and restarts only owned CatMCP processes after sustained failure.

Select the matching package manifest, then build the scheme:

```sh
cp control.rootless control
gmake clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless ARCHS="arm64 arm64e"

cp control.roothide control
gmake clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide ARCHS="arm64 arm64e"
```

Normal operation does not require Frida, an SSH foreground process, `touchd`,
or an App Store host application. Enable the original CatMCP preference toggle;
the launchd supervisor handles startup and recovery.
