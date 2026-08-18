#!/usr/bin/env python3
"""crontweakd -- converts crontab-syntax text into native launchd LaunchDaemons.

Listens on 127.0.0.1:53536. A client (the CronTweak Settings pane) connects,
sends the full crontab-style text, and closes its write side. This process
parses every non-comment/non-blank line as a 5-field cron schedule + shell
command, replaces the entire previously-generated set of per-job
LaunchDaemons with a freshly generated set (crontab -e semantics: Save always
replaces the whole schedule), and replies "OK <n>" or "ERR <details>".

Generated jobs run as the `mobile` user (matches interactive SSH), not root.
"""

import json
import os
import plistlib
import socket
import subprocess
import sys
import time
import traceback

LABEL_PREFIX = "com.ratush.crontweak.job"
LAUNCHDAEMONS_DIR = "/var/jb/Library/LaunchDaemons"
STATE_DIR = "/var/mobile/Library/CronTweak"
MANIFEST_PATH = os.path.join(STATE_DIR, "manifest.json")
LOG_DIR = "/var/mobile/Library/Logs/CronTweak"
PREFS_PATH = "/var/mobile/Library/Preferences/com.ratush.crontweak.plist"
CONTROL_HOST = "127.0.0.1"
CONTROL_PORT = 53536
MAX_EXPANSION = 1000
MAX_JOBS = 200


def log(msg):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(os.path.join(LOG_DIR, "daemon.log"), "a") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except Exception:
        pass


# ---------------------------------------------------------------- cron parse

FIELD_RANGES = {
    "Minute": (0, 59),
    "Hour": (0, 23),
    "Day": (1, 31),
    "Month": (1, 12),
    "Weekday": (0, 7),  # cron: both 0 and 7 mean Sunday
}


def parse_cron_field(token, lo, hi):
    """Return None for '*' (every value), else a sorted list of ints in [lo, hi]."""
    token = token.strip()
    if token == "*":
        return None
    values = set()
    for part in token.split(","):
        part = part.strip()
        if not part:
            raise ValueError("empty field segment")
        step = 1
        base = part
        if "/" in part:
            base, step_s = part.split("/", 1)
            if not step_s.isdigit() or int(step_s) <= 0:
                raise ValueError("bad step '%s'" % part)
            step = int(step_s)
        if base == "*":
            start = lo
            rng = range(lo, hi + 1)
        elif "-" in base:
            a_s, b_s = base.split("-", 1)
            if not (a_s.isdigit() and b_s.isdigit()):
                raise ValueError("bad range '%s'" % part)
            a, b = int(a_s), int(b_s)
            if a > b or a < lo or b > hi:
                raise ValueError("range out of bounds '%s' (expected %d-%d)" % (part, lo, hi))
            start = a
            rng = range(a, b + 1)
        else:
            if not base.isdigit():
                raise ValueError("bad value '%s'" % part)
            v = int(base)
            if v < lo or v > hi:
                raise ValueError("value out of bounds '%s' (expected %d-%d)" % (part, lo, hi))
            start = v
            rng = range(v, v + 1)
        for v in rng:
            if (v - start) % step == 0:
                values.add(v)
    if not values:
        raise ValueError("field resolved to no values")
    return sorted(values)


def parse_cron_line(line):
    """Return (fields_dict, command) or raise ValueError with a human message."""
    parts = line.split(None, 5)
    if len(parts) < 6:
        raise ValueError("expected 5 time fields + command, e.g. '*/15 * * * * echo hi'")
    minute_s, hour_s, day_s, month_s, dow_s, command = parts
    fields = {}
    for key, token in (
        ("Minute", minute_s), ("Hour", hour_s), ("Day", day_s),
        ("Month", month_s), ("Weekday", dow_s),
    ):
        lo, hi = FIELD_RANGES[key]
        fields[key] = parse_cron_field(token, lo, hi)
    if fields["Weekday"] is not None:
        fields["Weekday"] = sorted({0 if w == 7 else w for w in fields["Weekday"]})
    command = command.strip()
    if not command:
        raise ValueError("empty command")
    return fields, command


def expand_calendar_intervals(fields):
    """Cross-product of the restricted (non-None) fields into StartCalendarInterval dicts."""
    keys = [k for k, v in fields.items() if v is not None]
    if not keys:
        return [{}]  # every minute of every day
    total = 1
    for k in keys:
        total *= len(fields[k])
    if total > MAX_EXPANSION:
        raise ValueError("schedule expands to more than %d trigger points -- too broad" % MAX_EXPANSION)
    combos = [{}]
    for k in keys:
        new_combos = []
        for combo in combos:
            for v in fields[k]:
                nc = dict(combo)
                nc[k] = v
                new_combos.append(nc)
        combos = new_combos
    return combos


def parse_crontab_text(text):
    """Return (jobs, errors). jobs = list of (line_no, command, calendar_intervals)."""
    jobs, errors = [], []
    for i, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            fields, command = parse_cron_line(line)
            intervals = expand_calendar_intervals(fields)
            jobs.append((i, command, intervals))
        except ValueError as e:
            errors.append("line %d: %s" % (i, e))
    if len(jobs) > MAX_JOBS:
        errors.append("too many jobs (%d), max is %d" % (len(jobs), MAX_JOBS))
    return jobs, errors


# ------------------------------------------------------------- launchd side

def job_label(index):
    return "%s%d" % (LABEL_PREFIX, index)


def write_plist(path, label, command, intervals):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    log_path = os.path.join(LOG_DIR, "%s.log" % label)
    plist = {
        "Label": label,
        "ProgramArguments": ["/bin/sh", "-c", command],
        "UserName": "mobile",
        "StartCalendarInterval": intervals,
        "StandardOutPath": log_path,
        "StandardErrorPath": log_path,
    }
    with open(path, "wb") as f:
        plistlib.dump(plist, f)
    os.chmod(path, 0o644)
    try:
        os.chown(path, 0, 0)
    except PermissionError as e:
        log("chown root:wheel failed for %s: %s" % (path, e))


def launchctl(*args):
    cmd = ["/var/jb/usr/bin/launchctl"] + list(args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def bootout_label(label):
    launchctl("bootout", "system/%s" % label)


def bootstrap_plist(path):
    return launchctl("bootstrap", "system", path)


def load_manifest():
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except Exception:
        return []


def save_manifest(labels):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(MANIFEST_PATH, "w") as f:
        json.dump(labels, f)
    try:
        os.chown(STATE_DIR, 501, 501)
        os.chown(MANIFEST_PATH, 501, 501)
    except PermissionError:
        pass


def apply_crontab_text(text):
    jobs, errors = parse_crontab_text(text)
    if errors:
        return False, errors, 0

    # 1. Full-replace: tear down every previously generated job first.
    for label in load_manifest():
        bootout_label(label)
        old_path = os.path.join(LAUNCHDAEMONS_DIR, "%s.plist" % label)
        try:
            os.remove(old_path)
        except FileNotFoundError:
            pass

    # 2. Write + bootstrap the fresh set.
    new_labels = []
    bootstrap_errors = []
    for idx, (line_no, command, intervals) in enumerate(jobs):
        label = job_label(idx)
        path = os.path.join(LAUNCHDAEMONS_DIR, "%s.plist" % label)
        try:
            write_plist(path, label, command, intervals)
            rc, out, err = bootstrap_plist(path)
            if rc != 0:
                bootstrap_errors.append("line %d: launchctl bootstrap failed (%s)" % (line_no, err or out))
                continue
            launchctl("enable", "system/%s" % label)
            new_labels.append(label)
        except Exception as e:
            bootstrap_errors.append("line %d: %s" % (line_no, e))

    save_manifest(new_labels)

    if bootstrap_errors:
        return False, bootstrap_errors, len(new_labels)
    return True, [], len(new_labels)


def purge_all():
    """Used by prerm-invoked --purge: bootout+remove every generated job."""
    for label in load_manifest():
        bootout_label(label)
        old_path = os.path.join(LAUNCHDAEMONS_DIR, "%s.plist" % label)
        try:
            os.remove(old_path)
        except FileNotFoundError:
            pass
    try:
        os.remove(MANIFEST_PATH)
    except FileNotFoundError:
        pass


# ------------------------------------------------------- prefs (daemon side)

def write_result_to_prefs(ok, errors, count):
    for path in (PREFS_PATH,):
        try:
            d = {}
            try:
                with open(path, "rb") as f:
                    d = plistlib.load(f)
            except Exception:
                pass
            d["LastAppliedOK"] = ok
            d["LastAppliedCount"] = count
            d["LastAppliedErrors"] = errors
            d["LastAppliedAt"] = time.strftime("%Y-%m-%d %H:%M:%S")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                plistlib.dump(d, f)
            os.chown(path, 501, 501)
            os.chmod(path, 0o644)
        except Exception as e:
            log("prefs mirror failed for %s: %s" % (path, e))


# -------------------------------------------------------------- control API

def handle_conn(conn):
    conn.settimeout(10)
    chunks = []
    try:
        while True:
            data = conn.recv(65536)
            if not data:
                break
            chunks.append(data)
    except socket.timeout:
        pass
    text = b"".join(chunks).decode("utf-8", errors="replace")
    log("APPLY request, %d bytes" % len(text))
    try:
        ok, errors, count = apply_crontab_text(text)
    except Exception as e:
        log("apply_crontab_text crashed: " + traceback.format_exc())
        ok, errors, count = False, ["internal error: %s" % e], 0
    write_result_to_prefs(ok, errors, count)
    reply = ("OK %d\n" % count) if ok else ("ERR " + " | ".join(errors) + "\n")
    try:
        conn.sendall(reply.encode("utf-8"))
    except Exception:
        pass
    conn.close()


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--purge":
        purge_all()
        return
    log("crontweakd starting")
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(STATE_DIR, exist_ok=True)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((CONTROL_HOST, CONTROL_PORT))
    srv.listen(4)
    log("listening on %s:%d" % (CONTROL_HOST, CONTROL_PORT))
    while True:
        try:
            conn, _addr = srv.accept()
            handle_conn(conn)
        except Exception:
            log("accept loop error: " + traceback.format_exc())
            time.sleep(1)


if __name__ == "__main__":
    main()
