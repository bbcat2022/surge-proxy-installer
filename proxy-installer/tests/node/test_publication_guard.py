import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("publication_guard", ROOT / "tools" / "publication_guard.py")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class PublicationGuardTests(unittest.TestCase):
    def test_rejects_requirement_documents_and_private_key(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "03. requirements.md").write_text("requirements", encoding="utf-8")
            (root / "script.sh").write_text("-----BEGIN " + "PRIVATE KEY-----", encoding="utf-8")
            failures = guard.inspect(root, ["03. requirements.md", "script.sh"], [])
        self.assertIn("blocked path: 03. requirements.md", failures)
        self.assertIn("possible credential: script.sh", failures)

    def test_rejects_everything_under_no_upload(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            private = root / "no-upload" / "notes.txt"
            private.parent.mkdir()
            private.write_text("internal only", encoding="utf-8")
            failures = guard.inspect(root, ["no-upload/notes.txt"], [])
        self.assertEqual(failures, ["blocked path: no-upload/notes.txt"])

    def test_local_denylist_rejects_real_value_without_tracking_it(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "script.sh").write_text("endpoint=vps.example.test", encoding="utf-8")
            failures = guard.inspect(root, ["script.sh"], ["vps.example.test"])
        self.assertEqual(failures, ["matches local private denylist: script.sh"])
