import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY_SCRIPT = ROOT / "lib" / "resources" / "binary.sh"


class BinaryResourceTests(unittest.TestCase):
    def run_binary(self, body, env=None):
        environment = dict(os.environ)
        if env:
            environment.update(env)
        return subprocess.run(["bash", "-c", f'source "{BINARY_SCRIPT}"; {body}'], text=True, capture_output=True, env=environment, check=False)

    def test_manifest_exposes_at_most_three_verified_candidates(self):
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / "manifest"
            checksum = "a" * 64
            manifest.write_text("\n".join(f"v1.0.{n}|2026-01-0{n}|https://example.test/{n}|{checksum}|raw|server" for n in range(1, 4)) + "\n", encoding="utf-8")
            result = self.run_binary(f'binary_list_candidates "{manifest}"')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(result.stdout.splitlines()), 3)

    def test_checksum_failure_keeps_active_binary_unchanged(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, active = root / "source", root / "active"
            source.write_text("new", encoding="utf-8"); source.chmod(0o700)
            active.write_text("old", encoding="utf-8"); active.chmod(0o700)
            curl = root / "curl"
            curl.write_text('#!/usr/bin/env bash\nprintf new > "$6"\n', encoding="utf-8"); curl.chmod(0o700)
            result = self.run_binary(f'binary_prepare https://example.test/x {"0"*64} raw server "{root}/work" false', {"CURL_BIN": str(curl)})
            content = active.read_text(encoding="utf-8")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(content, "old")

    def test_version_failure_does_not_replace_active_binary(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            candidate, active = root / "candidate", root / "active"
            candidate.write_text('#!/usr/bin/env bash\nexit 1\n', encoding="utf-8"); candidate.chmod(0o700)
            active.write_text("old", encoding="utf-8"); active.chmod(0o700)
            result = self.run_binary(f'binary_install_candidate "{candidate}" "{active}" --version false')
            content = active.read_text(encoding="utf-8")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(content, "old")

    def test_dry_run_does_not_download_or_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = self.run_binary(f'binary_prepare https://example.test/x {"0"*64} raw server "{root}/work" true')
            work_exists = (root / "work").exists()
        self.assertEqual(result.returncode, 0)
        self.assertFalse(work_exists)

    def test_zip_and_tar_candidates_extract_only_the_declared_member(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); curl = root / 'curl'; unzip = root / 'unzip'; tar = root / 'tar'
            curl.write_text('#!/usr/bin/env bash\nprintf archive > "$6"\n', encoding='utf-8')
            unzip.write_text('#!/usr/bin/env bash\n[ "$3" = "bin/server" ] || exit 1\nprintf zip-binary\n', encoding='utf-8')
            tar.write_text('#!/usr/bin/env bash\n[ "$3" = "bin/server" ] || exit 1\nprintf tar-binary\n', encoding='utf-8')
            for tool in (curl, unzip, tar): tool.chmod(0o700)
            checksum = hashlib.sha256(b'archive').hexdigest()
            env = {'CURL_BIN': str(curl), 'UNZIP_BIN': str(unzip), 'TAR_BIN': str(tar)}
            zip_result = self.run_binary(f'binary_prepare https://example.test/x {checksum} zip bin/server "{root}/zip" false', env)
            tar_result = self.run_binary(f'binary_prepare https://example.test/x {checksum} tar.gz bin/server "{root}/tar-work" false', env)
            zip_content = (root/'zip'/'candidate').read_text(encoding='utf-8')
            tar_content = (root/'tar-work'/'candidate').read_text(encoding='utf-8')
        self.assertEqual(zip_result.returncode, 0, zip_result.stderr)
        self.assertEqual(tar_result.returncode, 0, tar_result.stderr)
        self.assertEqual(zip_content, 'zip-binary')
        self.assertEqual(tar_content, 'tar-binary')

    def test_archive_member_failure_does_not_leave_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); curl = root / 'curl'; unzip = root / 'unzip'
            curl.write_text('#!/usr/bin/env bash\nprintf archive > "$6"\n', encoding='utf-8')
            unzip.write_text('#!/usr/bin/env bash\nexit 1\n', encoding='utf-8')
            curl.chmod(0o700); unzip.chmod(0o700)
            checksum = hashlib.sha256(b'archive').hexdigest()
            result = self.run_binary(f'binary_prepare https://example.test/x {checksum} zip bin/server "{root}/work" false', {'CURL_BIN': str(curl), 'UNZIP_BIN': str(unzip)})
            candidate_exists = (root/'work'/'candidate').exists()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(candidate_exists)


if __name__ == "__main__":
    unittest.main()
