import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CERTIFICATE = ROOT / "lib" / "resources" / "certificate.sh"


class CertificateResourceTests(unittest.TestCase):
    def run_certificate(self, body, env):
        return subprocess.run(["bash", "-c", f'source "{CERTIFICATE}"; {body}'], text=True, capture_output=True, env=env, check=False)

    def make_openssl(self, root):
        openssl = root / "openssl"
        openssl.write_text(
            '#!/usr/bin/env bash\n'
            '[ "${MOCK_OPENSSL_FAIL:-}" = 1 ] && exit 1\n'
            'case "$*" in *-pubkey*) printf "%s\\n" "${MOCK_CERT_PUBLIC_KEY:-same-key}";; '
            '*-pubout*) printf "%s\\n" "${MOCK_KEY_PUBLIC_KEY:-same-key}";; esac\n'
            'exit 0\n',
            encoding="utf-8",
        )
        openssl.chmod(0o700)
        return openssl

    def test_candidate_install_restore_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); openssl = self.make_openssl(root)
            candidate, snapshot, active = root / "candidate", root / "snapshot", root / "active"
            candidate.mkdir(); snapshot.mkdir()
            for directory, label in ((candidate, "new"), (snapshot, "old")):
                (directory / "cert.pem").write_text(f"{label}-cert", encoding="utf-8")
                (directory / "key.pem").write_text(f"{label}-key", encoding="utf-8")
            env = dict(os.environ, OPENSSL_BIN=str(openssl))
            installed = self.run_certificate(f'certificate_install_candidate "{candidate}/cert.pem" "{candidate}/key.pem" "{active}" false', env)
            restored = self.run_certificate(f'certificate_restore "{snapshot}" "{active}" false', env)
            content = (active / "cert.pem").read_text(encoding="utf-8")
            mode = stat.S_IMODE(os.stat(active / "key.pem").st_mode)
        self.assertEqual(installed.returncode, 0)
        self.assertEqual(restored.returncode, 0)
        self.assertEqual(content, "old-cert")
        self.assertEqual(mode, 0o600)

    def test_invalid_candidate_and_dry_run_do_not_replace_active_files(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); openssl = self.make_openssl(root)
            candidate, active = root / "candidate", root / "active"
            candidate.mkdir(); active.mkdir()
            (candidate / "cert.pem").write_text("candidate", encoding="utf-8")
            (candidate / "key.pem").write_text("key", encoding="utf-8")
            (active / "cert.pem").write_text("old", encoding="utf-8")
            (active / "key.pem").write_text("old-key", encoding="utf-8")
            env = dict(os.environ, OPENSSL_BIN=str(openssl), MOCK_OPENSSL_FAIL="1")
            invalid = self.run_certificate(f'certificate_install_candidate "{candidate}/cert.pem" "{candidate}/key.pem" "{active}" false', env)
            dry_env = dict(os.environ, OPENSSL_BIN=str(openssl))
            dry = self.run_certificate(f'certificate_install_candidate "{candidate}/cert.pem" "{candidate}/key.pem" "{active}" true', dry_env)
            content = (active / "cert.pem").read_text(encoding="utf-8")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(dry.returncode, 0)
        self.assertEqual(content, "old")

    def test_http01_prechecks_are_read_only_and_report_dns_and_port80(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text)
            getent = root / "getent"; ss = root / "ss"
            getent.write_text('#!/usr/bin/env bash\nprintf "203.0.113.8 STREAM example\\n"\n', encoding="utf-8")
            ss.write_text('#!/usr/bin/env bash\nprintf "State Recv-Q Send-Q Local Address:Port Peer Address:Port\\nLISTEN 0 1 0.0.0.0:80 0.0.0.0:*\\n"\n', encoding="utf-8")
            getent.chmod(0o700); ss.chmod(0o700)
            env = dict(os.environ, GETENT_BIN=str(getent), SS_BIN=str(ss))
            dns = self.run_certificate('certificate_precheck_dns example.com 203.0.113.8', env)
            port = self.run_certificate('certificate_observe_tcp80', env)
            mismatch = self.run_certificate('certificate_precheck_dns example.com 203.0.113.9', env)
        self.assertEqual(dns.returncode, 0, dns.stderr)
        self.assertIn('dns-match=true', dns.stdout)
        self.assertIn('tcp-80-listener=present', port.stdout)
        self.assertNotEqual(mismatch.returncode, 0)

    def test_acme_candidate_issue_validates_before_activation_and_timer_is_rendered(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); acme = root / 'acme'; openssl = self.make_openssl(root); calls = root / 'acme-calls'
            acme.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$ACME_CALLS"\nif [ "$1" = "--install-cert" ]; then while [ "$#" -gt 0 ]; do case "$1" in --fullchain-file) shift; printf cert > "$1";; --key-file) shift; printf key > "$1";; esac; shift; done; fi\n', encoding='utf-8')
            acme.chmod(0o700)
            env = dict(os.environ, ACME_BIN=str(acme), OPENSSL_BIN=str(openssl), ACME_CALLS=str(calls))
            candidate = root / 'candidate'
            issued = self.run_certificate(f'certificate_issue_candidate example.com "{candidate}" false', env)
            candidate_created = (candidate / 'cert.pem').exists()
            service = self.run_certificate('certificate_build_renew_service proxy-installer-cert.service "/usr/local/bin/renew"', env)
            timer = self.run_certificate('certificate_build_renew_timer proxy-installer-cert.timer proxy-installer-cert.service', env)
            dry = self.run_certificate(f'certificate_issue_candidate example.com "{root}/dry" true', env)
            dry_created = (root / 'dry').exists()
            acme_calls = calls.read_text(encoding='utf-8')
        self.assertEqual(issued.returncode, 0, issued.stderr)
        self.assertTrue(candidate_created)
        self.assertIn('ExecStart=/usr/local/bin/renew', service.stdout)
        self.assertIn('OnCalendar=daily', timer.stdout)
        self.assertIn('Unit=proxy-installer-cert.service', timer.stdout)
        self.assertNotIn('[Service]', timer.stdout)
        self.assertEqual(dry.returncode, 0)
        self.assertFalse(dry_created)
        self.assertIn('--issue --standalone --server letsencrypt -d example.com', acme_calls)

    def test_mismatched_certificate_key_and_mixed_active_pair_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); openssl = self.make_openssl(root)
            candidate = root / "candidate"; active = root / "active"
            candidate.mkdir(); active.mkdir()
            (candidate / "cert.pem").write_text("cert", encoding="utf-8")
            (candidate / "key.pem").write_text("key", encoding="utf-8")
            (active / "cert.pem").write_text("old-cert", encoding="utf-8")
            mismatch = self.run_certificate(
                f'certificate_validate_candidate "{candidate}/cert.pem" "{candidate}/key.pem"',
                dict(os.environ, OPENSSL_BIN=str(openssl), MOCK_CERT_PUBLIC_KEY="cert-key", MOCK_KEY_PUBLIC_KEY="other-key"),
            )
            mixed = self.run_certificate(
                f'certificate_install_candidate "{candidate}/cert.pem" "{candidate}/key.pem" "{active}" false',
                dict(os.environ, OPENSSL_BIN=str(openssl)),
            )
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertNotEqual(mixed.returncode, 0)

    def test_failed_acme_install_removes_partial_candidate(self):
        with tempfile.TemporaryDirectory() as temp_text:
            root = Path(temp_text); openssl = self.make_openssl(root); acme = root / "acme"
            acme.write_text(
                '#!/usr/bin/env bash\n'
                'if [ "$1" = --install-cert ]; then '
                'while [ "$#" -gt 0 ]; do [ "$1" = --fullchain-file ] && { shift; printf partial > "$1"; }; shift; done; '
                'exit 1; fi\n'
                'exit 0\n',
                encoding="utf-8",
            )
            acme.chmod(0o700)
            candidate = root / "candidate"
            result = self.run_certificate(
                f'certificate_issue_candidate example.com "{candidate}" false',
                dict(os.environ, OPENSSL_BIN=str(openssl), ACME_BIN=str(acme)),
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(candidate.exists())


if __name__ == "__main__":
    unittest.main()
