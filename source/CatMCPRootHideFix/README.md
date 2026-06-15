# CatMCP RootHide Fix

RootHide compatibility helper for `com.catmcp.daemon` 1.0.3.

The release package:

- adds `catmcp-rootfix.dylib` as a direct `LC_LOAD_DYLIB` dependency;
- translates `/var/mobile` file operations into the active RootHide jbroot;
- repairs `/var/jb/bin/sh` and shell-spawned directory operations;
- restarts the watchdog in the correct `user/501` launchd domain;
- preserves the original CatMCP entitlements.

`audit-all-tools.mjs` was used to verify all 42 MCP functions after installation
and again after a watchdog restart.

Fishhook is included under its BSD license in `rootfix/FISHHOOK-LICENSE.txt`.
