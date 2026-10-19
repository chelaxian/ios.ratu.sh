# Published build

Package com.ratush.lockdown 2.0+rootless1, ordinary Dopamine rootless, iOS 17.0.
These corresponding build sources are from commit 718f9dd6c7a515eb50702445f63687ba7401c7b4
of chelaxian/lockdown-dopamine; upstream roothide/lockdown eab851c7ac6b295cd418882f3270c1fde4f8cc6e.
GPL-3.0, see LICENSE. Build instructions: README.md and .github/workflows/build.yml.
macOS CI 39290916398, Xcode 16.4, iPhoneOS SDK 18.5, pinned Theos.
DEB SHA256 f74e59dda216fe52f65f73227997bdb1b60d2fdd10a3218eb857307e5bc62b04.

Validated 2026-10-19 on iPhone15,3, iOS17.0/21A329, Dopamine3.0.10, ElleKit1.2:
fresh WebContent injection; actual forceGCSlowPaths=true/useConcurrentGC=false;
haveABadTime caller in lockdown2 during native JSGlobalContext creation;
Safari navigation, arrays/objects/typed arrays, DOM, JSON, loop and Worker.
JIT stays enabled. No fresh WebContent crashes observed in the short test.
The build-time README's pending validation section is superseded by this record.
Third-party WKWebView apps, media, reboot/rejail, performance and resistance to
specific exploits are not tested. No preference pane, Balanced compile-time level1.
If using a Choicy whitelist, allow lockdown2 for com.apple.WebKit.WebContent.
