#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

int main(int argc, char **argv) {
	const char *mode = "apply";
	if (argc > 1 && argv[1] && argv[1][0]) {
		mode = argv[1];
	}
	if (strcmp(mode, "apply") != 0 && strcmp(mode, "sync") != 0 && strcmp(mode, "daemon") != 0) {
		fprintf(stderr, "invalid mode\n");
		return 2;
	}

	setgid(0);
	setuid(0);

	char shellCommand[1536];
	snprintf(shellCommand, sizeof(shellCommand),
		"for r in /var/containers/Bundle/Application/.jbroot-* /var/jb ''; do "
		"if [ -x \"$r/usr/bin/python3\" ] && [ -f \"$r/usr/libexec/etchosts17.py\" ]; then "
		"exec \"$r/usr/bin/python3\" \"$r/usr/libexec/etchosts17.py\" '%s'; "
		"fi; "
		"done; "
		"exec /usr/bin/python3 /usr/libexec/etchosts17.py '%s'",
		mode, mode);
	execl("/bin/sh", "sh", "-c", shellCommand, (char *)NULL);

	char resolved[PATH_MAX];
	char prefix[PATH_MAX];
	char pythonPath[PATH_MAX];
	char scriptPath[PATH_MAX];
	const char *script = "/usr/libexec/etchosts17.py";
	if (realpath(argv[0], resolved)) {
		char *suffix = strstr(resolved, "/usr/libexec/etchosts17ctl");
		if (suffix) {
			size_t prefixLen = (size_t)(suffix - resolved);
			if (prefixLen < sizeof(prefix)) {
				memcpy(prefix, resolved, prefixLen);
				prefix[prefixLen] = '\0';
				snprintf(pythonPath, sizeof(pythonPath), "%s/usr/bin/python3", prefix);
				snprintf(scriptPath, sizeof(scriptPath), "%s/usr/libexec/etchosts17.py", prefix);
				script = scriptPath;
			}
		}
	}
	if (script == scriptPath) {
		char command[1024];
		snprintf(command, sizeof(command), "'%s' '%s' '%s'", pythonPath, scriptPath, mode);
		execl("/bin/sh", "sh", "-c", command, (char *)NULL);
	}
	const char *interpreters[] = {
		"/usr/bin/python3.9",
		"/usr/bin/python3",
		"/var/jb/usr/bin/python3.9",
		"/var/jb/usr/bin/python3",
		NULL
	};
	for (int i = 0; interpreters[i]; i++) {
		if (!interpreters[i]) continue;
		execl(interpreters[i], "python3", script, mode, (char *)NULL);
	}
	perror("execl");
	return 127;
}
