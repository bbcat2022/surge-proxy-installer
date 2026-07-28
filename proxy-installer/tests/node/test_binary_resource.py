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
            manifest.write_text("\n".join(f"v1.0.{n}|stable|2026-01-0{n}|linux-amd64|test|https://example.test/{n}|{checksum}|raw|server" for n in range(1, 4)) + "\n", encoding="utf-8")
            result = self.run_binary(f'binary_list_candidates "{manifest}"')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(result.stdout.splitlines()), 3)

    def test_candidate_filter_excludes_wrong_architecture_and_consumer(self):
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / "manifest"
            checksum = "a" * 64
            manifest.write_text(
                f"v1.0.0|stable|2026-01-01|linux-arm64|anytls|https://example.test/a|{checksum}|raw|server\n"
                f"v1.0.1|stable|2026-01-02|linux-amd64|other|https://example.test/b|{checksum}|raw|server\n"
                f"v1.0.2|beta|2026-01-03|linux-amd64|anytls,other|https://example.test/c|{checksum}|raw|server\n",
                encoding="utf-8",
            )
            result = self.run_binary(f'binary_list_candidates "{manifest}" linux-amd64 anytls')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split("|", 1)[0], "v1.0.2")

    def test_selected_version_must_be_one_of_displayed_candidates(self):
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / "manifest"
            checksum = "a" * 64
            manifest.write_text(
                f"v1.2.3|stable|2026-01-01|linux-amd64|snell|https://example.test/x|{checksum}|raw|server\n",
                encoding="utf-8",
            )
            selected = self.run_binary(f'binary_select_candidate "{manifest}" v1.2.3 linux-amd64 snell')
            unknown = self.run_binary(f'binary_select_candidate "{manifest}" v1.2.4 linux-amd64 snell')
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertNotEqual(unknown.returncode, 0)

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
            work_exists = (root / "work").exists()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(content, "old")
        self.assertFalse(work_exists)

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

    def test_existing_work_directory_and_unsafe_archive_member_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            work = root / "work"
            work.mkdir()
            marker = work / "candidate"
            marker.write_text("stale", encoding="utf-8")
            checksum = "a" * 64
            existing = self.run_binary(f'binary_prepare https://example.test/x {checksum} raw server "{work}" false')
            unsafe = self.run_binary(f'binary_prepare https://example.test/x {checksum} zip ../server "{root}/unsafe" false')
            marker_content = marker.read_text(encoding="utf-8")
        self.assertNotEqual(existing.returncode, 0)
        self.assertNotEqual(unsafe.returncode, 0)
        self.assertEqual(marker_content, "stale")

    def test_version_probe_argument_cannot_inject_an_extra_command(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            candidate = root / "candidate"
            active = root / "active"
            marker = root / "injected"
            candidate.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            candidate.chmod(0o700)
            result = self.run_binary(
                f'binary_install_candidate "{candidate}" "{active}" \'--version;touch {marker}\' false'
            )
            active_exists = active.exists()
            marker_exists = marker.exists()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(active_exists)
        self.assertFalse(marker_exists)

    def test_restore_is_atomic_and_restores_executable_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            backup = root / "backup"
            active = root / "active"
            backup.write_text("old", encoding="utf-8")
            backup.chmod(0o600)
            active.write_text("new", encoding="utf-8")
            active.chmod(0o700)
            result = self.run_binary(f'binary_restore "{backup}" "{active}" false')
            leftovers = list(root.glob(".*.restore.*"))
            restored_content = active.read_text(encoding="utf-8")
            restored_mode = active.stat().st_mode & 0o777
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(restored_content, "old")
        self.assertEqual(restored_mode, 0o700)
        self.assertEqual(leftovers, [])


if __name__ == "__main__":
    unittest.main()
