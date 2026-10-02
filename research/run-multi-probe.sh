#!/bin/sh
set -eu
daemon=$(ps -A -o pid,comm | awk '$2 == "/var/jb/usr/libexec/appsplitvpnd" {print $1}')
cleanup() {
 /var/mobile/asv-multi-session-probe restore
 kill -CONT "$daemon"
}
trap cleanup EXIT HUP INT TERM
# Freeze the old supervisor so it cannot fight the bounded experiment.
kill -STOP "$daemon"
chown 501:501 /var/mobile/asv040-profile-backup.archive
/var/mobile/asv-multi-session-probe "$@"
