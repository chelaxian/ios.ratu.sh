#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "fishhook.h"

static char g_jbroot[PATH_MAX];
static FILE *(*original_fopen)(const char *, const char *);
static DIR *(*original_opendir)(const char *);
static int (*original_remove)(const char *);
static int (*original_posix_spawn)(pid_t *, const char *,
                                   const posix_spawn_file_actions_t *,
                                   const posix_spawnattr_t *,
                                   char *const[], char *const[]);

static int starts_with(const char *value, const char *prefix) {
    return value && prefix && strncmp(value, prefix, strlen(prefix)) == 0;
}

static const char *translated_path(const char *path, char *buffer, size_t size) {
    if (!path || g_jbroot[0] == '\0' || starts_with(path, g_jbroot)) return path;
    const char *suffix = NULL;
    if (strcmp(path, "/var/mobile") == 0 || starts_with(path, "/var/mobile/")) {
        suffix = path;
    } else if (strcmp(path, "/private/var/mobile") == 0 ||
               starts_with(path, "/private/var/mobile/")) {
        suffix = path + strlen("/private");
    }
    if (!suffix || snprintf(buffer, size, "%s%s", g_jbroot, suffix) >= (int)size) {
        return path;
    }
    return buffer;
}

static FILE *rootfix_fopen(const char *path, const char *mode) {
    char translated[PATH_MAX];
    return original_fopen(translated_path(path, translated, sizeof(translated)), mode);
}

static DIR *rootfix_opendir(const char *path) {
    char translated[PATH_MAX];
    return original_opendir(translated_path(path, translated, sizeof(translated)));
}

static int rootfix_remove(const char *path) {
    char translated[PATH_MAX];
    return original_remove(translated_path(path, translated, sizeof(translated)));
}

static char *translated_command(const char *command) {
    const char *mobile = "/var/mobile";
    const char *private_mobile = "/private/var/mobile";
    size_t extra = 0;
    for (const char *cursor = command; *cursor;) {
        if (starts_with(cursor, private_mobile)) {
            extra += strlen(g_jbroot) + strlen(mobile) - strlen(private_mobile);
            cursor += strlen(private_mobile);
        } else if (starts_with(cursor, mobile)) {
            extra += strlen(g_jbroot);
            cursor += strlen(mobile);
        } else {
            cursor++;
        }
    }

    char *result = malloc(strlen(command) + extra + 1);
    if (!result) return NULL;
    char *output = result;
    for (const char *cursor = command; *cursor;) {
        if (starts_with(cursor, private_mobile)) {
            output += sprintf(output, "%s%s", g_jbroot, mobile);
            cursor += strlen(private_mobile);
        } else if (starts_with(cursor, mobile)) {
            output += sprintf(output, "%s%s", g_jbroot, mobile);
            cursor += strlen(mobile);
        } else {
            *output++ = *cursor++;
        }
    }
    *output = '\0';
    return result;
}

static int rootfix_posix_spawn(pid_t *pid, const char *path,
                               const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attributes,
                               char *const argv[], char *const envp[]) {
    char **replacement_argv = NULL;
    char *replacement_command = NULL;
    if (argv && argv[1] && argv[2] && strcmp(argv[1], "-c") == 0) {
        size_t count = 0;
        while (argv[count]) count++;
        replacement_command = translated_command(argv[2]);
        replacement_argv = calloc(count + 1, sizeof(char *));
        if (replacement_command && replacement_argv) {
            for (size_t index = 0; index < count; index++) replacement_argv[index] = argv[index];
            replacement_argv[2] = replacement_command;
        } else {
            free(replacement_command);
            free(replacement_argv);
            replacement_command = NULL;
            replacement_argv = NULL;
        }
    }

    int result = original_posix_spawn(pid, path, actions, attributes,
                                      replacement_argv ? replacement_argv : argv, envp);
    free(replacement_command);
    free(replacement_argv);
    return result;
}

static void ensure_jbroot_link(void) {
    struct stat info;
    if (lstat("/var/jb", &info) == 0) {
        if (S_ISDIR(info.st_mode)) {
            unlink("/var/jb/bin/sh");
            rmdir("/var/jb/bin");
            if (rmdir("/var/jb") != 0) return;
        } else if (S_ISLNK(info.st_mode)) {
            unlink("/var/jb");
        } else {
            return;
        }
    }
    symlink(g_jbroot, "/var/jb");
}

__attribute__((constructor))
static void catmcp_rootfix_init(void) {
    uint32_t size = sizeof(g_jbroot);
    if (_NSGetExecutablePath(g_jbroot, &size) != 0) return;
    char *suffix = strstr(g_jbroot, "/usr/bin/catmcp");
    if (!suffix) return;
    *suffix = '\0';

    original_fopen = dlsym(RTLD_DEFAULT, "fopen");
    original_opendir = dlsym(RTLD_DEFAULT, "opendir");
    original_remove = dlsym(RTLD_DEFAULT, "remove");
    original_posix_spawn = dlsym(RTLD_DEFAULT, "posix_spawn");
    struct rebinding bindings[] = {
        {"fopen", rootfix_fopen, NULL},
        {"opendir", rootfix_opendir, NULL},
        {"remove", rootfix_remove, NULL},
        {"posix_spawn", rootfix_posix_spawn, NULL},
    };
    rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
    ensure_jbroot_link();
}
