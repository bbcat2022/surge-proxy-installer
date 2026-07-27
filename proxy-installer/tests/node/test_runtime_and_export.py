import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "lib" / "resources" / "runtime.sh"
EXPORT = ROOT / "lib" / "export" / "surge.sh"


class RuntimeAndExportTests(unittest.TestCase):
    def run_script(self, script: Path, body: str, env=None):
        environment = dict(os.environ)
        if env:
            environment.update(env)
        return subprocess.run(["bash", "-c", f'source "{script}"; {body}'], text=True, capture_output=True, check=False, env=environment)

    def test_runtime_write_restore_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text)
            candidate, snapshot, target = root / "candidate", root / "snapshot", root / "out" / "runtime"
            candidate.write_text("new-secret", encoding="utf-8")
            snapshot.write_text("old-secret", encoding="utf-8")
            written = self.run_script(RUNTIME, f'runtime_write "{candidate}" "{target}" false')
            restored = self.run_script(RUNTIME, f'runtime_restore "{snapshot}" "{target}" false')
            content, mode = target.read_text(encoding="utf-8"), stat.S_IMODE(os.stat(target).st_mode)
        self.assertEqual(written.returncode, 0)
        self.assertEqual(restored.returncode, 0)
        self.assertEqual(content, "old-secret")
        self.assertEqual(mode, 0o600)

    def test_runtime_dry_run_and_missing_candidate_leave_target_unchanged(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text)
            candidate, target = root / "candidate", root / "target"
            candidate.write_text("new", encoding="utf-8"); target.write_text("old", encoding="utf-8")
            dry_run = self.run_script(RUNTIME, f'runtime_write "{candidate}" "{target}" true')
            missing = self.run_script(RUNTIME, f'runtime_write "{root}/missing" "{target}" false')
            content = target.read_text(encoding="utf-8")
        self.assertEqual(dry_run.returncode, 0)
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(content, "old")

    def test_surge_export_uses_entries_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text)
            first, second, target = root / "one", root / "two", root / "out" / "surge.conf"
            first.write_text("Snell = snell, example.com, 443, psk=test, version=6\n", encoding="utf-8")
            second.write_text("AnyTLS = anytls, example.com, 443, password=test\n", encoding="utf-8")
            result = self.run_script(EXPORT, f'surge_export_fragment "{target}" false "{first}" "{second}"')
            content, mode = target.read_text(encoding="utf-8"), stat.S_IMODE(os.stat(target).st_mode)
        self.assertEqual(result.returncode, 0)
        self.assertTrue(content.startswith("[Proxy]\n"))
        self.assertIn("Snell = snell", content)
        self.assertIn("AnyTLS = anytls", content)
        self.assertEqual(mode, 0o600)

    def test_surge_export_dry_run_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text)
            entry, target = root / "entry", root / "out" / "surge.conf"
            entry.write_text("Snell = snell, example.com, 443, psk=test, version=6\n", encoding="utf-8")
            result = self.run_script(EXPORT, f'surge_export_fragment "{target}" true "{entry}"')
            exists = target.exists()
        self.assertEqual(result.returncode, 0)
        self.assertFalse(exists)

    def test_surge_qr_is_atomic_private_and_requires_generator_success(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); fragment = root / "fragment"; target = root / "out" / "node.png"
            fragment.write_text("[Proxy]\nNode = snell, x, 443\n", encoding="utf-8")
            qr = root / "qrencode"; qr.write_text('#!/usr/bin/env bash\nprintf png > "$4"\n', encoding="utf-8"); qr.chmod(0o700)
            success = self.run_script(EXPORT, f'surge_export_qr "{fragment}" "{target}" false', {"QRENCODE_BIN": str(qr)})
            mode = stat.S_IMODE(target.stat().st_mode)
            failed_qr = root / "failed-qr"; failed_qr.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8"); failed_qr.chmod(0o700)
            failed = self.run_script(EXPORT, f'surge_export_qr "{fragment}" "{root}/failed.png" false', {"QRENCODE_BIN": str(failed_qr)})
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertEqual(mode, 0o600)
        self.assertNotEqual(failed.returncode, 0)


if __name__ == "__main__":
    unittest.main()
