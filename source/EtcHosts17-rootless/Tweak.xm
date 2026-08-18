#import <Foundation/Foundation.h>
#import <notify.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern "C" bool os_variant_has_internal_diagnostics(const char *subsystem) __attribute__((weak_import));

#define EtcHosts17_DEFAULT_PATH "/etc/hosts"
#define EtcHosts17_VARJB_PATH "/var/jb/etc/hosts"
#define EtcHosts17_ROOTFS_HOSTS_PATH "/rootfs/etc/hosts"
#define EtcHosts17_ROOTFS_MERGED_PATH "/rootfs/private/var/mobile/Library/EtcHosts17/hosts.merged"
#define EtcHosts17_JB_MERGED_PATH "/var/mobile/Library/EtcHosts17/hosts.merged"
#define EtcHosts17_NOTIFY_APPLY "com.ratush.etchosts17.apply"

static int gApplyNotifyToken = 0;
typedef void (*EtcHosts17LibSandyApplyProfile)(const char *);

static bool EtcHosts17ShouldRedirect(const char *path, const char *mode) {
	if (!path) return false;
	if (strcmp(path, EtcHosts17_DEFAULT_PATH) != 0 &&
		strcmp(path, EtcHosts17_VARJB_PATH) != 0 &&
		strcmp(path, EtcHosts17_ROOTFS_HOSTS_PATH) != 0) {
		return false;
	}
	if (!mode) return true;
	return strchr(mode, 'r') != NULL && strchr(mode, 'w') == NULL && strchr(mode, 'a') == NULL;
}

static bool EtcHosts17ShouldRedirectOpen(const char *path, int flags) {
	if (!path) return false;
	if (strcmp(path, EtcHosts17_DEFAULT_PATH) != 0 &&
		strcmp(path, EtcHosts17_VARJB_PATH) != 0 &&
		strcmp(path, EtcHosts17_ROOTFS_HOSTS_PATH) != 0) {
		return false;
	}
	int accessMode = flags & O_ACCMODE;
	return accessMode == O_RDONLY;
}

static void EtcHosts17ApplySandboxProfile(void) {
	EtcHosts17LibSandyApplyProfile applyProfile =
		(EtcHosts17LibSandyApplyProfile)dlsym(RTLD_DEFAULT, "libSandy_applyProfile");
	if (!applyProfile) {
		void *handle = dlopen("libsandy.dylib", RTLD_NOW);
		if (handle) {
			applyProfile = (EtcHosts17LibSandyApplyProfile)dlsym(handle, "libSandy_applyProfile");
		}
	}
	if (applyProfile) applyProfile("EtcHosts17");
}

static void EtcHosts17Log(const char *message) {
	const char *paths[] = {
		"/tmp/etchosts17.inject.log",
		"/var/tmp/etchosts17.inject.log",
		"/rootfs/private/var/mobile/Library/EtcHosts17/inject.log",
		"/var/mobile/Library/EtcHosts17/inject.log",
		NULL
	};
	for (int i = 0; paths[i]; i++) {
		int fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
		if (fd >= 0) {
			dprintf(fd, "%s\n", message);
			close(fd);
			return;
		}
	}
}

%hookf(FILE *, fopen, const char *path, const char *mode) {
	if (EtcHosts17ShouldRedirect(path, mode)) {
		FILE *merged = %orig(EtcHosts17_ROOTFS_MERGED_PATH, mode);
		if (merged) return merged;
		merged = %orig(EtcHosts17_JB_MERGED_PATH, mode);
		if (merged) return merged;
	}
	return %orig(path, mode);
}

%hookf(int, open, const char *path, int flags, ...) {
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}

	bool redirected = EtcHosts17ShouldRedirectOpen(path, flags);
	const char *target = redirected ? EtcHosts17_ROOTFS_MERGED_PATH : path;
	int fd = %orig(target, flags, mode);
	if (fd < 0 && redirected) {
		fd = %orig(EtcHosts17_JB_MERGED_PATH, flags, mode);
	}
	return fd;
}

%hookf(int, openat, int fd, const char *path, int flags, ...) {
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}

	bool redirected = EtcHosts17ShouldRedirectOpen(path, flags);
	const char *target = redirected ? EtcHosts17_ROOTFS_MERGED_PATH : path;
	int result = %orig(fd, target, flags, mode);
	if (result < 0 && redirected) {
		result = %orig(fd, EtcHosts17_JB_MERGED_PATH, flags, mode);
	}
	return result;
}

%group Diagnostics

%hookf(bool, os_variant_has_internal_diagnostics, const char *subsystem) {
	if (subsystem && strcmp(subsystem, "com.apple.mDNSResponder") == 0) {
		return true;
	}
	return %orig(subsystem);
}

%end

%ctor {
	@autoreleasepool {
		EtcHosts17ApplySandboxProfile();
		EtcHosts17Log("EtcHosts17 constructor reached");
		if (getuid() == 0) return;
		EtcHosts17Log("EtcHosts17 initializing mDNSResponder hooks");
		%init(Diagnostics);
		notify_register_dispatch(EtcHosts17_NOTIFY_APPLY, &gApplyNotifyToken, dispatch_get_main_queue(), ^(int token) {
			(void)token;
			exit(0);
		});
		%init;
	}
}
