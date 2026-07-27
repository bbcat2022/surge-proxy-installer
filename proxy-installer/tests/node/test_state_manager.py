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
                result = self.run_state(f'state_save_success_revision "{state_root}" "{config}" "r{number}" "test operation"')
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
            copied = state_root / "transactions" / "op-1" / "resources" / "runtime.yaml"
            mode = stat.S_IMODE(os.stat(copied).st_mode)
            exists = copied.exists()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(exists)
        self.assertEqual(mode, 0o600)


if __name__ == "__main__":
    unittest.main()
