# CatMCP Clean RootHide Package

This source recipe rebuilds the clean RootHide-converted CatMCP 1.0.3 package
from the pre-modification device backup.

It intentionally excludes:

- the obsolete `catmcp-rootfix.dylib`;
- the custom watchdog;
- the `catmcp.dylib.roothidepatch` link owned by the separate
  `com.ratush.catmcp-roothide-fix` package.

The published package version remains `1.0.3`, so Sileo does not advertise
the retired `1.0.3-roothidefix3` build as an update.
