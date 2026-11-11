"""Exercise the unattended invocation contract, not just ACME success responses."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

RESOURCE = Path(__file__).resolve().parents[2] / 'lib/resources/certificate.sh'


class CertificateAcmeStateTests(unittest.TestCase):
    def fixture(self, root, ecc=True, record=True):
        home = root / 'acme-state'
        domain_dir = home / ('node.example.com_ecc' if ecc else 'node.example.com')
        domain_dir.mkdir(parents=True)
        if record:
            (domain_dir / 'node.example.com.conf').touch()
        calls = root / 'calls.jsonl'
        acme = root / 'acme'
        acme.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
home = Path(os.environ['EXPECTED_ACME_HOME'])
with open(os.environ['ACME_CALLS'], 'a') as f:
    f.write(json.dumps(a) + '\\n')
for flag in ('--home', '--config-home', '--cert-home'):
    if flag not in a or a[a.index(flag)+1] != str(home):
        sys.exit(31)
if ('--ecc' in a) != (os.environ['EXPECTED_ECC'] == 'true'):
    sys.exit(32)
domain = 'node.example.com'
record = home / (domain + ('_ecc' if '--ecc' in a else '')) / (domain + '.conf')
if a[0] == '--issue':
    record.parent.mkdir(parents=True, exist_ok=True)
    record.touch()
elif not record.is_file():
    sys.exit(33)
if a[0] == '--install-cert':
    cert = Path(a[a.index('--fullchain-file')+1])
    key = Path(a[a.index('--key-file')+1])
    cert.write_text('fresh-certificate')
    key.write_text('fresh-key')
    (home / 'installed-path').write_text(str(cert))
elif a[0] == '--renew':
    # A real renewal reuses the destination remembered by --install-cert.
    if not Path((home / 'installed-path').read_text()).parent.is_dir():
        sys.exit(34)
    sys.exit(int(os.environ.get('RENEW_STATUS', '2')))
else:
    if a[0] != '--issue':
        sys.exit(35)
''', encoding='utf-8')
        acme.chmod(0o700)
        openssl = root / 'openssl'
        openssl.write_text('#!/bin/sh\ncase "$*" in *-pubkey*|*-pubout*) echo key;; esac\n', encoding='utf-8')
        openssl.chmod(0o700)
        env = dict(os.environ, ACME_HOME=str(home), EXPECTED_ACME_HOME=str(home),
                   EXPECTED_ECC=str(ecc).lower(), ACME_CALLS=str(calls),
                   ACME_BIN=str(acme), OPENSSL_BIN=str(openssl))
        # Match a system service: no inherited HOME, current directory '/'.
        env.pop('HOME', None)
        return home, calls, env

    def run_resource(self, body, env):
        return subprocess.run(['bash', '-euo', 'pipefail', '-c', f'source "{RESOURCE}"\n{body}'],
                              cwd='/', env=env, text=True, capture_output=True)

    def test_existing_ecc_renews_without_home_and_survives_deleted_workdir(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home, calls, env = self.fixture(root)
            for name in ('first-work', 'second-work'):
                candidate = root / name
                result = self.run_resource(f'certificate_refresh_candidate node.example.com "{candidate}" false', env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((candidate / 'cert.pem').read_text(), 'fresh-certificate')
                shutil.rmtree(candidate)
            rows = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual([row[0] for row in rows], ['--install-cert', '--renew', '--install-cert'] * 2)
            remembered = Path((home / 'installed-path').read_text())
            self.assertTrue(remembered.is_file())
            self.assertEqual(remembered.stat().st_mode & 0o777, 0o600)

    def test_existing_rsa_does_not_silently_switch_to_ecc(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, _, env = self.fixture(root, ecc=False)
            result = self.run_resource(f'certificate_refresh_candidate node.example.com "{root}/candidate" false', env)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_fresh_issue_and_later_renewal_share_the_same_state(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, _, env = self.fixture(root, record=False)
            result = self.run_resource(
                f'certificate_issue_candidate node.example.com "{root}/issue" false\n'
                f'certificate_refresh_candidate node.example.com "{root}/renew" false', env)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_record_fails_instead_of_claiming_nothing_is_due(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, calls, env = self.fixture(root, record=False)
            result = self.run_resource(f'certificate_refresh_candidate node.example.com "{root}/candidate" false', env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('missing-acme-record', result.stderr)
            self.assertFalse(calls.exists())
            self.assertFalse((root / 'candidate').exists())

    def test_failed_renewal_never_produces_an_activation_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, _, env = self.fixture(root)
            env['RENEW_STATUS'] = '1'
            result = self.run_resource(f'certificate_refresh_candidate node.example.com "{root}/candidate" false', env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'candidate').exists())

    def test_default_state_directory_is_independent_of_home(self):
        env = dict(os.environ)
        env.pop('HOME', None)
        env.pop('ACME_HOME', None)
        result = self.run_resource('printf "%s" "$ACME_HOME"', env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '/root/.acme.sh')

    def test_real_expired_certificate_is_rejected_before_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            key, valid, expired = root / 'key.pem', root / 'valid.pem', root / 'expired.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                            '-subj', '/CN=node.example.com', '-keyout', str(key), '-out', str(valid)],
                           check=True, capture_output=True)
            # Explicit dates work on both macOS LibreSSL and Debian OpenSSL.
            request = root / 'request.csr'
            subprocess.run(['openssl', 'req', '-new', '-key', str(key), '-subj', '/CN=node.example.com',
                            '-out', str(request)], check=True, capture_output=True)
            (root / 'index').touch()
            (root / 'serial').write_text('01\n')
            (root / 'issued').mkdir()
            ca = root / 'ca.cnf'
            ca.write_text(f'[ca]\ndefault_ca=test\n[test]\ndatabase={root}/index\nserial={root}/serial\n'
                          f'new_certs_dir={root}/issued\ndefault_md=sha256\npolicy=policy\n'
                          '[policy]\ncommonName=supplied\n')
            subprocess.run(['openssl', 'ca', '-selfsign', '-batch', '-config', str(ca),
                            '-keyfile', str(key), '-cert', str(valid), '-in', str(request),
                            '-startdate', '20200101000000Z', '-enddate', '20200102000000Z',
                            '-out', str(expired)], check=True, capture_output=True)
            active = root / 'active'
            active.mkdir()
            (active / 'cert.pem').write_text('keep-old')
            (active / 'key.pem').write_text('keep-key')
            env = dict(os.environ, OPENSSL_BIN='openssl')
            good = self.run_resource(f'certificate_validate_candidate "{valid}" "{key}"', env)
            bad = self.run_resource(f'certificate_install_candidate "{expired}" "{key}" "{active}" false', env)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn('expired-or-invalid', bad.stderr)
            self.assertEqual((active / 'cert.pem').read_text(), 'keep-old')


if __name__ == '__main__':
    unittest.main()
