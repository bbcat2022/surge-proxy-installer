import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
LATEST=ROOT/'bootstrap'/'latest.sh'

class LatestBootstrapSmokeTests(unittest.TestCase):
 def test_latest_entry_fetches_checksum_then_calls_verified_installer(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); calls=root/'calls'; curl=root/'curl'; shell=root/'bash'
   curl.write_text(
    '#!/usr/bin/env bash\n'
    'printf "curl:%s\\n" "$*" >> "$CALLS"\n'
    'while [ "$#" -gt 0 ]; do\n'
    ' [ "$1" = --output ] && { shift; output="$1"; }\n'
    ' shift\n'
    'done\n'
    'case "$output" in\n'
    ' *release.sha256) printf "%064d  proxy-installer-local.tar.gz\\n" 0 > "$output";;\n'
    ' *install.sh) printf "#!/usr/bin/env bash\\nexit 0\\n" > "$output";;\n'
    'esac\n'
   ); curl.chmod(0o700)
   shell.write_text('#!/usr/bin/env bash\nprintf "bash:%s\\n" "$*" >> "$CALLS"\n'); shell.chmod(0o700)
   env=dict(
    os.environ,CURL_BIN=str(curl),BASH_BIN=str(shell),CALLS=str(calls),
    PROXY_INSTALLER_RELEASE_URL='https://example.test/latest/proxy-installer-local.tar.gz',
    PROXY_INSTALLER_CHECKSUM_URL='https://example.test/latest/proxy-installer-local.tar.gz.sha256',
    PROXY_INSTALLER_BOOTSTRAP_URL='https://example.test/install.sh',
   )
   result=subprocess.run(['bash',str(LATEST)],env=env,text=True,capture_output=True,check=False)
   recorded=calls.read_text()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('release.sha256',recorded)
  self.assertIn('install.sh',recorded)
  self.assertIn('--release-url https://example.test/latest/proxy-installer-local.tar.gz',recorded)
  self.assertIn(f'--sha256 {"0" * 64}',recorded)
  self.assertIn('--version latest',recorded)

 def test_invalid_checksum_never_calls_installer(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); calls=root/'calls'; curl=root/'curl'; shell=root/'bash'
   curl.write_text(
    '#!/usr/bin/env bash\n'
    'while [ "$#" -gt 0 ]; do [ "$1" = --output ] && { shift; output="$1"; }; shift; done\n'
    'printf invalid > "$output"\n'
   ); curl.chmod(0o700)
   shell.write_text('#!/usr/bin/env bash\ntouch "$CALLS"\n'); shell.chmod(0o700)
   env=dict(
    os.environ,CURL_BIN=str(curl),BASH_BIN=str(shell),CALLS=str(calls),
    PROXY_INSTALLER_RELEASE_URL='https://example.test/release.tar.gz',
    PROXY_INSTALLER_CHECKSUM_URL='https://example.test/release.tar.gz.sha256',
    PROXY_INSTALLER_BOOTSTRAP_URL='https://example.test/install.sh',
   )
   result=subprocess.run(['bash',str(LATEST)],env=env,text=True,capture_output=True,check=False)
   installer_called=calls.exists()
  self.assertNotEqual(result.returncode,0)
  self.assertFalse(installer_called)

if __name__=='__main__': unittest.main()
