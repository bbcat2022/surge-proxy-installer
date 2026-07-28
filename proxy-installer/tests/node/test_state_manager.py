import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE_SCRIPT = ROOT / "lib" / "config" / "state.sh"
LOCAL_PACKAGES = ROOT.parent / ".python-packages"


class StateManagerTests(unittest.TestCase):
    def run_state(self, script: str):
        environment = dict(os.environ, PYTHONPATH=str(LOCAL_PACKAGES))
        return subprocess.run(["bash", "-c", f'source "{STATE_SCRIPT}"; {script}'], text=True, capture_output=True, env=environment, check=False)

    def test_initialization_and_separate_state_updates(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            initialized = self.run_state(f'state_initialize "{config}"')
            desired = self.run_state(f'state_patch "{config}" \'{{"desired": {{"snell": {{"psk": "test-secret"}}}}}}\'')
            applied = self.run_state(f'state_commit_applied "{config}" \'{{"revision": 1}}\'')
            observed = self.run_state(f'state_record_observed "{config}" \'{{"snell": {{"active": true, "checked_at": "test"}}}}\'')
            read = self.run_state(f'state_read "{config}"')
            mode = stat.S_IMODE(os.stat(config).st_mode)
        self.assertEqual(initialized.returncode, 0, initialized.stderr)
        self.assertEqual(desired.returncode, 0, desired.stderr)
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertEqual(observed.returncode, 0, observed.stderr)
        data = json.loads(read.stdout)["data"]
        self.assertEqual(data["desired"]["snell"]["psk"], "***REDACTED***")
        self.assertEqual(data["applied"]["revision"], 1)
        self.assertTrue(data["observed"]["snell"]["active"])
        self.assertEqual(mode, 0o600)

    def test_six_revisions_keep_the_newest_five(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            state_root = root / "state"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            for number in range(1, 7):
                result = self.run_state(f'state_save_success_revision "{state_root}" "{config}" "r{number}" deploy "test operation"')
                self.assertEqual(result.returncode, 0, result.stderr)
            listed = self.run_state(f'state_list_success_revisions "{state_root}"')
            revisions = listed.stdout.splitlines()
            first_mode = stat.S_IMODE(os.stat(state_root / "revisions" / "r2" / "config.yaml").st_mode)
        self.assertEqual(revisions, ["r2", "r3", "r4", "r5", "r6"])
        self.assertEqual(first_mode, 0o600)

    def test_snapshot_copies_config_and_resource_with_private_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            resource = root / "runtime.yaml"
            resource.write_text("secret: test\n", encoding="utf-8")
            state_root = root / "state"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            result = self.run_state(f'state_create_transaction_snapshot "{state_root}" "{config}" "op-1" "{resource}"')
            snapshot = state_root / "transactions" / "op-1"
            copied = snapshot / "resources" / "0001-runtime.yaml"
            mode = stat.S_IMODE(os.stat(copied).st_mode)
            exists = copied.exists()
            manifest = (snapshot / "snapshot-manifest.txt").read_text(encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(exists)
        self.assertEqual(mode, 0o600)
        self.assertIn("resource_count=1", manifest)

    def test_snapshot_rejects_unsafe_id_and_never_publishes_partial_capture(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            state_root = root / "state"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            unsafe = self.run_state(f'state_create_transaction_snapshot "{state_root}" "{config}" "../escape"')
            failed = self.run_state(
                f'state_create_transaction_snapshot "{state_root}" "{config}" "op-2" "{root}/missing"'
            )
            transaction_root = state_root / "transactions"
            leftovers = list(transaction_root.iterdir()) if transaction_root.exists() else []
        self.assertNotEqual(unsafe.returncode, 0)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(leftovers, [])

    def test_success_revision_records_metadata_and_preserves_same_named_resources(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            first = root / "runtime" / "config.json"
            second = root / "unit" / "config.json"
            first.parent.mkdir(); second.parent.mkdir()
            first.write_text("runtime", encoding="utf-8")
            second.write_text("unit", encoding="utf-8")
            state_root = root / "state"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            result = self.run_state(
                f'STATE_DATE_BIN="{root}/date"; '
                f'printf \'#!/usr/bin/env bash\\nprintf \"2026-07-28T00:00:00Z\\\\n\"\\n\' > "$STATE_DATE_BIN"; '
                f'chmod 700 "$STATE_DATE_BIN"; '
                f'state_save_success_revision "{state_root}" "{config}" r1 deploy "installed services" "{first}" "{second}"'
            )
            revision = state_root / "revisions" / "r1"
            manifest = (revision / "revision-manifest.txt").read_text(encoding="utf-8")
            saved = sorted(path.read_text(encoding="utf-8") for path in (revision / "resources").iterdir())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("operation_type=deploy", manifest)
        self.assertIn("completed_at=2026-07-28T00:00:00Z", manifest)
        self.assertIn("resource_count=2", manifest)
        self.assertEqual(saved, ["runtime", "unit"])

    def test_failed_revision_capture_does_not_publish_partial_revision(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / "config.yaml"
            state_root = root / "state"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            failed = self.run_state(
                f'state_save_success_revision "{state_root}" "{config}" r1 deploy "must fail" "{root}/missing"'
            )
            listed = self.run_state(f'state_list_success_revisions "{state_root}"')
            leftovers = list((state_root / "revisions").iterdir())
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(listed.stdout, "")
        self.assertEqual(leftovers, [])

    def test_operation_status_uses_controlled_history_interface(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / "config.yaml"
            self.assertEqual(self.run_state(f'state_initialize "{config}"').returncode, 0)
            recorded = self.run_state(
                f'state_record_operation "{config}" op-9 certificate rollback-success "old certificate restored"'
            )
            read = self.run_state(f'state_read "{config}"')
            operation = json.loads(read.stdout)["data"]["history"]["last_operation"]
        self.assertEqual(recorded.returncode, 0, recorded.stderr)
        self.assertEqual(operation["id"], "op-9")
        self.assertEqual(operation["type"], "certificate")
        self.assertEqual(operation["status"], "rollback-success")


if __name__ == "__main__":
    unittest.main()
