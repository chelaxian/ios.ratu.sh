import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "daemon", Path(__file__).resolve().parents[1] / "crontweakd/crontweakd.py")
daemon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(daemon)


class DaemonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        for name, value in {
            "LAUNCHDAEMONS_DIR": root / "jobs",
            "STATE_DIR": root / "state",
            "MANIFEST_PATH": root / "state/manifest.json",
            "LOG_DIR": root / "logs",
            "PREFS_PATH": root / "prefs.plist",
        }.items():
            p = patch.object(daemon, name, str(value))
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(daemon.os, "chown", create=True)
        p.start()
        self.addCleanup(p.stop)
        os.makedirs(daemon.LOG_DIR)

    def test_day_and_weekday_are_alternative_triggers(self):
        fields, _ = daemon.parse_cron_line("0 9 1 * 1 echo hello")
        self.assertEqual(daemon.expand_calendar_intervals(fields),
                         [{"Minute": 0, "Hour": 9, "Day": 1},
                          {"Minute": 0, "Hour": 9, "Weekday": 1}])

    def test_every_five_minutes_and_sunday(self):
        jobs, errors = daemon.parse_crontab_text("*/5 * * * 7 echo hello")
        self.assertEqual(errors, [])
        self.assertEqual(len(jobs[0][2]), 12)
        self.assertEqual(jobs[0][2][-1], {"Minute": 55, "Weekday": 0})

    def test_invalid_input_keeps_existing_jobs(self):
        daemon.save_manifest([daemon.job_label(0)])
        with patch.object(daemon, "bootout_label") as stop:
            ok, errors, _ = daemon.apply_crontab_text("not a schedule")
        self.assertFalse(ok)
        self.assertTrue(errors)
        stop.assert_not_called()
        self.assertEqual(daemon.load_manifest(), [daemon.job_label(0)])

    def test_rootless_execution_environment(self):
        path = str(Path(daemon.LAUNCHDAEMONS_DIR) / "job.plist")
        daemon.write_plist(path, daemon.job_label(0), "uiopen test", [{}])
        with open(path, "rb") as f:
            job = plistlib.load(f)
        self.assertEqual(job["ProgramArguments"][0], "/var/jb/bin/sh")
        self.assertEqual(job["UserName"], "mobile")
        self.assertEqual(job["WorkingDirectory"], "/var/mobile")
        self.assertTrue(job["EnvironmentVariables"]["PATH"].startswith("/var/jb/usr/bin:"))

    def test_only_missing_leading_executable_is_migrated(self):
        with patch.object(daemon.os.path, "exists", return_value=False), \
             patch.object(daemon.os.path, "isfile", return_value=True), \
             patch.object(daemon.os, "access", return_value=True):
            self.assertEqual(daemon.normalize_rootless_commands(
                "*/5 * * * * /usr/bin/uiopen --bundleid test\n"),
                "*/5 * * * * /var/jb/usr/bin/uiopen --bundleid test\n")
            text = "* * * * * echo /usr/bin/uiopen\n"
            self.assertEqual(daemon.normalize_rootless_commands(text), text)
        with patch.object(daemon.os.path, "exists", return_value=True):
            text = "* * * * * /bin/echo hello\n"
            self.assertEqual(daemon.normalize_rootless_commands(text), text)

    def test_clear_logs_preserves_schedule_and_open_file(self):
        # Windows cannot truncate a file opened by another process with these
        # sharing flags; this descriptor test runs on the macOS builder.
        if not hasattr(os, "O_NOFOLLOW"):
            self.skipTest("requires POSIX open flags")
        daemon.save_manifest([daemon.job_label(0)])
        with open(daemon.PREFS_PATH, "wb") as f:
            plistlib.dump({"CronText": "* * * * * echo test",
                          "LastAppliedErrors": ["old error"], "LastAppliedAt": "old"}, f)
        path = Path(daemon.LOG_DIR) / (daemon.job_label(0) + ".log")
        path.write_text("old output")
        unrelated = Path(daemon.LOG_DIR) / "unrelated.txt"
        unrelated.write_text("keep")
        with open(path, "a") as descriptor:
            self.assertEqual(daemon.clear_logs(), 1)
            self.assertEqual(path.stat().st_size, 0)
            descriptor.write("new output")
            descriptor.flush()
        self.assertEqual(path.read_text(), "new output")
        self.assertEqual(unrelated.read_text(), "keep")
        self.assertEqual(daemon.load_manifest(), [daemon.job_label(0)])
        with open(daemon.PREFS_PATH, "rb") as f:
            self.assertEqual(plistlib.load(f), {"CronText": "* * * * * echo test"})

    def test_failed_bootstrap_restores_previous_schedule(self):
        label = daemon.job_label(0)
        path = Path(daemon.LAUNCHDAEMONS_DIR) / (label + ".plist")
        daemon.write_plist(str(path), label, "echo original", [{}])
        original = path.read_bytes()
        daemon.save_manifest([label])
        with patch.object(daemon, "launchctl", return_value=(0, "", "")), \
             patch.object(daemon, "bootstrap_plist", side_effect=[
                 (1, "", "simulated failure"), (0, "", "")]):
            ok, errors, count = daemon.apply_crontab_text("* * * * * echo replacement")
        self.assertFalse(ok)
        self.assertIn("simulated failure", errors[0])
        self.assertEqual(count, 1)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(daemon.load_manifest(), [label])

    def test_manifest_rejects_unrelated_labels(self):
        os.makedirs(daemon.STATE_DIR)
        Path(daemon.MANIFEST_PATH).write_text(json.dumps([
            daemon.job_label(0), "../../unrelated", "com.apple.test", 123]))
        self.assertEqual(daemon.load_manifest(), [daemon.job_label(0)])


if __name__ == "__main__":
    unittest.main()
