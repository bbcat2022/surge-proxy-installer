import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "config_tool.py"
SAMPLE = "schema_version: 1\nconfig_revision: 1\ndesired:\n  snell:\n    psk: test-secret\napplied: {}\nobserved: {}\nhistory: {}\n"
sys.path.insert(0, str(ROOT / "tools"))
import config_tool


class ConfigToolTests(unittest.TestCase):
    def run_tool(self, config: Path, *args: str):
        completed = subprocess.run([sys.executable, str(TOOL), "--config", str(config), *args], text=True, capture_output=True, check=False)
        return completed.returncode, json.loads(completed.stdout)

    def make_config(self, directory: Path, content: str = SAMPLE) -> Path:
        path = directory / "config.yaml"
        path.write_text(content, encoding="utf-8")
        return path

    def test_read_redacts_sensitive_values(self):
        with tempfile.TemporaryDirectory() as temp:
            code, result = self.run_tool(self.make_config(Path(temp)), "read")
        self.assertEqual(code, 0)
        self.assertEqual(result["data"]["desired"]["snell"]["psk"], "***REDACTED***")

    def test_deployment_plan_is_redacted_and_only_contains_enabled_protocols(self):
        content = """schema_version: 1
config_revision: 0
desired:
  protocols:
    snell:
      enabled: true
      port: 443
      psk: private-snell-secret
      client_address: node.example.com
    anytls:
      enabled: false
      port: 8443
      password: private-anytls-secret
      domain: node.example.com
applied: {}
observed: {}
history: {}
"""
        with tempfile.TemporaryDirectory() as temp:
            code, result = self.run_tool(self.make_config(Path(temp), content), "deployment-plan")
        self.assertEqual(code, 0)
        self.assertEqual(result["data"]["protocols"], [{"name": "snell", "port": 443, "client_address": "node.example.com"}])
        self.assertNotIn("private-snell-secret", json.dumps(result))

    def test_deployment_env_is_shell_quoted_and_contains_required_secret_only_for_orchestrator(self):
        content = """schema_version: 1
config_revision: 0
desired:
  protocols:
    snell:
      enabled: true
      port: 443
      psk: private-snell-secret
      client_address_type: domain
      client_address: node.example.com
      mode: default
applied: {}
observed: {}
history: {}
"""
        with tempfile.TemporaryDirectory() as temp:
            completed = subprocess.run([sys.executable, str(TOOL), "--config", str(self.make_config(Path(temp), content)), "deployment-env"], text=True, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0)
        self.assertIn("DEPLOY_SELECTED_PROTOCOLS=snell", completed.stdout)
        self.assertIn("SNELL_PSK=private-snell-secret", completed.stdout)

    def test_invalid_yaml_preserves_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp), "schema_version: [broken")
            original = path.read_text(encoding="utf-8")
            code, result = self.run_tool(path, "validate")
            self.assertEqual(path.read_text(encoding="utf-8"), original)
        self.assertEqual(code, 2)
        self.assertEqual(result["category"], "validation")

    def test_incompatible_schema_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp), SAMPLE.replace("schema_version: 1", "schema_version: 2"))
            code, result = self.run_tool(path, "validate")
        self.assertEqual(code, 2)
        self.assertEqual(result["summary"], "configuration schema_version is incompatible")

    def test_patch_is_atomic_and_sets_private_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            code, result = self.run_tool(path, "patch", "--patch", '{"config_revision": 2, "desired": {"snell": {"port": 8443}}}')
            content = path.read_text(encoding="utf-8")
            mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(code, 0)
        self.assertTrue(result["changed"])
        self.assertIn("config_revision: 2", content)
        self.assertIn("port: 8443", content)
        self.assertEqual(mode, 0o600)

    def test_invalid_patch_does_not_change_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            original = path.read_text(encoding="utf-8")
            code, result = self.run_tool(path, "patch", "--patch", '{"unsupported": true}')
            self.assertEqual(path.read_text(encoding="utf-8"), original)
        self.assertEqual(code, 2)
        self.assertEqual(result["category"], "validation")

    def test_dry_run_does_not_write(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            original = path.read_text(encoding="utf-8")
            code, result = self.run_tool(path, "--dry-run", "patch", "--patch", '{"config_revision": 2}')
            self.assertEqual(path.read_text(encoding="utf-8"), original)
        self.assertEqual(code, 0)
        self.assertTrue(result["dry_run"])

    def test_operation_summary_is_validated_and_recorded_without_secrets(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            code, result = self.run_tool(
                path,
                "record-operation",
                "--operation-id", "deploy-001",
                "--operation-type", "deploy",
                "--status", "pending",
                "--summary", "prepared three protocol candidates",
                "--failed-stage", "client-export",
                "--repair-advice", "regenerate the client profile before retrying",
            )
            stored = config_tool.load_yaml(path, 1)["history"]["last_operation"]
            invalid_code, invalid = self.run_tool(
                path,
                "record-operation",
                "--operation-id", "../unsafe",
                "--operation-type", "deploy",
                "--status", "pending",
                "--summary", "invalid",
            )
        self.assertEqual(code, 0, result)
        self.assertEqual(stored, {
            "id": "deploy-001",
            "type": "deploy",
            "status": "pending",
            "summary": "prepared three protocol candidates",
            "failed_stage": "client-export",
            "repair_advice": "regenerate the client profile before retrying",
        })
        self.assertEqual(invalid_code, 2)
        self.assertEqual(invalid["category"], "validation")

    def test_operation_failure_context_rejects_multiline_or_unsafe_values(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            bad_stage_code, bad_stage = self.run_tool(
                path, "record-operation",
                "--operation-id", "deploy-002",
                "--operation-type", "deploy",
                "--status", "dirty",
                "--summary", "rollback incomplete",
                "--failed-stage", "../runtime",
            )
            bad_advice_code, bad_advice = self.run_tool(
                path, "record-operation",
                "--operation-id", "deploy-002",
                "--operation-type", "deploy",
                "--status", "dirty",
                "--summary", "rollback incomplete",
                "--repair-advice", "inspect snapshot\nthen retry",
            )
        self.assertEqual(bad_stage_code, 2)
        self.assertEqual(bad_stage["category"], "validation")
        self.assertEqual(bad_advice_code, 2)
        self.assertEqual(bad_advice["category"], "validation")

    def test_replace_failure_preserves_original_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            original = path.read_text(encoding="utf-8")
            replacement = config_tool.merge_mapping(config_tool.load_yaml(path, 1), {"config_revision": 2})
            with mock.patch("config_tool.os.replace", side_effect=OSError("injected failure")):
                with self.assertRaises(config_tool.ToolError) as raised:
                    config_tool.atomic_write(path, replacement, 1)
            self.assertEqual(path.read_text(encoding="utf-8"), original)
        self.assertEqual(raised.exception.category, "external")

    def test_temporary_write_creation_failure_preserves_original_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.make_config(Path(temp))
            original = path.read_text(encoding="utf-8")
            replacement = config_tool.merge_mapping(config_tool.load_yaml(path, 1), {"config_revision": 2})
            with mock.patch("config_tool.tempfile.mkstemp", side_effect=OSError("injected failure")):
                with self.assertRaises(config_tool.ToolError) as raised:
                    config_tool.atomic_write(path, replacement, 1)
            self.assertEqual(path.read_text(encoding="utf-8"), original)
        self.assertEqual(raised.exception.category, "external")


if __name__ == "__main__":
    unittest.main()
