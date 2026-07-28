import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYSTEMD_SCRIPT = ROOT / "lib" / "resources" / "systemd.sh"


class SystemdResourceTests(unittest.TestCase):
    def make_mock_commands(self, directory: Path):
        calls = directory / "calls"
        systemctl = directory / "systemctl"
        journalctl = directory / "journalctl"
        systemctl.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\n[ -n "${MOCK_FAIL:-}" ] && [ "${MOCK_FAIL}" = "$1" ] && exit 1\n[ "$1" = "is-active" ] && { printf active; exit 0; }\n[ "$1" = "is-enabled" ] && { printf enabled; exit 0; }\nexit 0\n', encoding="utf-8")
        journalctl.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\nprintf "log line\\n"\n', encoding="utf-8")
        systemctl.chmod(0o700)
        journalctl.chmod(0o700)
        return systemctl, journalctl, calls

    def run_systemd(self, body: str, temp: Path, systemctl: Path, journalctl: Path, calls: Path):
        environment = dict(os.environ, SYSTEMCTL_BIN=str(systemctl), JOURNALCTL_BIN=str(journalctl), MOCK_CALLS=str(calls))
        return subprocess.run(["bash", "-c", f'source "{SYSTEMD_SCRIPT}"; {body}'], text=True, capture_output=True, env=environment, check=False)

    def test_unit_write_is_private_and_restorable(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            systemctl, journalctl, calls = self.make_mock_commands(temp)
            candidate = temp / "candidate.service"
            snapshot = temp / "snapshot.service"
            candidate.write_text("[Service]\nExecStart=/new\n", encoding="utf-8")
            snapshot.write_text("[Service]\nExecStart=/old\n", encoding="utf-8")
            unit_dir = temp / "units"
            written = self.run_systemd(f'systemd_write_unit "{unit_dir}" "example.service" "{candidate}"', temp, systemctl, journalctl, calls)
            restored = self.run_systemd(f'systemd_restore_unit "{unit_dir}" "example.service" "{snapshot}"', temp, systemctl, journalctl, calls)
            target = unit_dir / "example.service"
            content = target.read_text(encoding="utf-8")
            mode = stat.S_IMODE(os.stat(target).st_mode)
        self.assertEqual(written.returncode, 0, written.stderr)
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertIn("/old", content)
        self.assertEqual(mode, 0o600)

    def test_actions_observation_and_logs_use_replaceable_commands(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            systemctl, journalctl, calls = self.make_mock_commands(temp)
            action = self.run_systemd("systemd_action example.service restart", temp, systemctl, journalctl, calls)
            observed = self.run_systemd("systemd_observe example.service", temp, systemctl, journalctl, calls)
            logs = self.run_systemd("systemd_logs example.service 50", temp, systemctl, journalctl, calls)
            recorded = calls.read_text(encoding="utf-8")
        self.assertEqual(action.returncode, 0)
        self.assertIn("active=active", observed.stdout)
        self.assertIn("enabled=enabled", observed.stdout)
        self.assertIn("log line", logs.stdout)
        self.assertIn("restart example.service", recorded)
        self.assertIn("-n 50", recorded)

    def test_dry_run_does_not_call_system_commands(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            systemctl, journalctl, calls = self.make_mock_commands(temp)
            result = self.run_systemd("systemd_action example.service restart true; systemd_observe example.service true; systemd_logs example.service 50 true", temp, systemctl, journalctl, calls)
            called = calls.exists()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(called)

    def test_timer_units_are_accepted_for_installation_and_actions(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            systemctl, journalctl, calls = self.make_mock_commands(temp)
            candidate = temp / "candidate.timer"
            candidate.write_text("[Timer]\nOnCalendar=daily\n", encoding="utf-8")
            unit_dir = temp / "units"
            result = self.run_systemd(f'systemd_write_unit "{unit_dir}" "example.timer" "{candidate}"; systemd_action example.timer enable', temp, systemctl, journalctl, calls)
            recorded = calls.read_text(encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("enable example.timer", recorded)

    def test_command_failure_and_invalid_log_limit_are_visible(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            systemctl, journalctl, calls = self.make_mock_commands(temp)
            environment = dict(os.environ, SYSTEMCTL_BIN=str(systemctl), JOURNALCTL_BIN=str(journalctl), MOCK_CALLS=str(calls), MOCK_FAIL="restart")
            failed = subprocess.run(["bash", "-c", f'source "{SYSTEMD_SCRIPT}"; systemd_action example.service restart'], text=True, capture_output=True, env=environment, check=False)
            invalid = self.run_systemd("systemd_logs example.service 101", temp, systemctl, journalctl, calls)
        self.assertNotEqual(failed.returncode, 0)
        self.assertNotEqual(invalid.returncode, 0)


if __name__ == "__main__":
    unittest.main()
