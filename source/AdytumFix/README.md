# Adytum Fix 1.0.0

Companion fix for Adytum 1.1 on iOS 17.0 / Dopamine rootless. Package: `com.ratush.adytumfix`.

Adytum's arm64e code passes stack blocks with an unsigned Objective-C `isa` into UIKit. The recorded SpringBoard crashes occur while UIKit copies those blocks during icon-menu `UIAction` creation and `UIView` animations. A separate animation crash has no Offloader frame.

This helper hooks three public UIKit class methods. Before forwarding the original arguments, it signs the missing stack-block `isa` with the DA key, address diversity and discriminator `0x6AE1`. It preserves the original callbacks and captured objects.

The guard requires all of the following:

- The block is within the current thread's stack bounds.
- Its class pointer is exactly the unsigned `_NSConcreteStackBlock` address, and its flags identify a signature-bearing stack block.
- Its invocation function belongs to `Adytum.dylib` with arm64e UUID `5FFA5340-E6C8-3E5B-9084-089FD354EFB3`.

Already signed blocks, heap/global blocks, other tweaks and other Adytum builds are not modified. No Adytum binary, preferences, protected code pages or bootstrap files are patched by the package.

## Install

Install **Adytum Fix** from https://ios.ratu.sh, then respring. Allow `AdytumFix` for SpringBoard if you use an explicit Choicy allow list. Enable Adytum's **Show in 3D Touch menu** option.

The package depends on Adytum 1.1. It has no preferences panel: repair is automatic. Offloader is optional.

## Verification

- macOS/Xcode CI run 37473286270 builds universal arm64/arm64e with current PTRAUTH ABI.
- On the physical iPhone15,3 / iOS 17.0 (21A329), Dopamine 3.0.10, a temporary Settings-only check passed **1006 assertions**. It converts valid stack blocks into the same unsigned-isa state, repairs them, verifies the signature exactly matches the compiler's signature, copies and invokes them, and passes them to `UIAction` and both animation methods.
- The check also verified object lifetimes and rejection of nil, nonblock, already signed, heap, and unrelated-origin inputs.
- The production helper is installed, its log confirms all three hooks, and SpringBoard survives with Adytum's menu setting enabled.
- The owner confirmed long press on several app icons and execution of an Adytum menu action work. The helper recorded eight repaired Adytum blocks; the same SpringBoard process remained alive, and no new SpringBoard crash appeared.

Bounded runtime log: `/var/mobile/Library/Logs/AdytumFix.log`. The temporary test module is removed after validation and is not in the DEB.

## Uninstall / rollback

Disable Adytum's menu option, remove only `com.ratush.adytumfix`, then respring. Removing the helper does not remove Adytum.

## ABI references

- [Clang Pointer Authentication ABI](https://clang.llvm.org/docs/PointerAuthentication.html#blocks)
- [Apple Blocks runtime structures](https://github.com/apple-oss-distributions/libclosure/blob/main/Block_private.h)

The initial helper candidate mistakenly used DB instead of DA; the hardware check rejected it before any SpringBoard installation. Only the passing DA version is released.
