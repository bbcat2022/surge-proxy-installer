import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIREWALL_SCRIPT = ROOT / "lib" / "resources" / "firewall.sh"


class FirewallResourceTests(unittest.TestCase):
    def run_firewall(self, body: str, environment=None):
        env = dict(os.environ)
        if environment:
            env.update(environment)
        return subprocess.run(["bash", "-c", f'source "{FIREWALL_SCRIPT}"; {body}'], text=True, capture_output=True, env=env, check=False)

    def test_transport_validation_distinguishes_tcp_udp_and_range(self):
        self.assertEqual(self.run_firewall("firewall_validate_rule tcp 443").returncode, 0)
        self.assertEqual(self.run_firewall("firewall_validate_rule udp 443").returncode, 0)
        self.assertEqual(self.run_firewall("firewall_validate_rule udp-range 20000-50000").returncode, 0)
        self.assertNotEqual(self.run_firewall("firewall_validate_rule udp-range 50000-20000").returncode, 0)
        self.assertNotEqual(self.run_firewall("firewall_validate_rule tcp 65536").returncode, 0)

    def test_manual_mode_only_renders_rules_and_cloud_reminder(self):
        result = self.run_firewall("firewall_apply manual manual false tcp:443 udp:8443 udp-range:20000-50000")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("allow tcp 443", result.stdout)
        self.assertIn("allow udp 8443", result.stdout)
        self.assertIn("allow udp-range 20000-50000", result.stdout)
        self.assertIn("cloud-security-group", result.stdout)

    def test_unsupported_environment_downgrades_to_manual(self):
        result = self.run_firewall("firewall_apply auto manual false tcp:443")
        self.assertEqual(result.returncode, 0)
        self.assertIn("allow tcp 443", result.stdout)

    def test_auto_ufw_uses_exact_transport_rules_and_dry_run_is_safe(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            calls = temp / "calls"
            ufw = temp / "ufw"
            ufw.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\n', encoding="utf-8")
            ufw.chmod(0o700)
            environment = {"UFW_BIN": str(ufw), "MOCK_CALLS": str(calls)}
            applied = self.run_firewall("firewall_apply auto ufw false tcp:443 udp:8443 udp-range:20000-50000", environment)
            recorded = calls.read_text(encoding="utf-8")
            calls.unlink()
            dry_run = self.run_firewall("firewall_apply auto ufw true tcp:443", environment)
            called_in_dry_run = calls.exists()
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertIn("allow 443/tcp", recorded)
        self.assertIn("allow 8443/udp", recorded)
        self.assertIn("allow 20000-50000/udp", recorded)
        self.assertEqual(dry_run.returncode, 0)
        self.assertFalse(called_in_dry_run)

    def test_auto_write_failure_is_returned(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            ufw = temp / "ufw"
            ufw.write_text('#!/usr/bin/env bash\nexit 1\n', encoding="utf-8")
            ufw.chmod(0o700)
            result = self.run_firewall("firewall_apply auto ufw false udp:8443", {"UFW_BIN": str(ufw)})
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
