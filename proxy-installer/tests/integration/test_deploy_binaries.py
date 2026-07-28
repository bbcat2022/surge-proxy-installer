import hashlib, os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
ORCHESTRATOR=ROOT/'lib'/'orchestrators'/'deploy_binaries.sh'

class DeployBinariesTests(unittest.TestCase):
 def test_selects_first_pinned_candidate_and_installs_verified_binary(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); manifests=root/'manifests'; manifests.mkdir(); payload=b'#!/usr/bin/env bash\necho v1.2.3\n'; checksum=hashlib.sha256(payload).hexdigest()
   manifests.joinpath('snell-amd64.txt').write_text(f'v1.2.3|stable|2026-01-01|linux-amd64|snell|https://example.test/snell|{checksum}|raw|snell-server\n',encoding='utf-8')
   curl=root/'curl'; curl.write_text('#!/usr/bin/env bash\nfor arg in "$@"; do [ "$previous" = --output ] && printf "#!/usr/bin/env bash\\necho v1.2.3\\n" > "$arg"; previous="$arg"; done\n',encoding='utf-8'); curl.chmod(0o700)
   work=root/'work'; active=root/'active' ; env=dict(os.environ,CURL_BIN=str(curl))
   body=f'''source "{ORCHESTRATOR}"
deploy_binary_prepare_pinned snell "{manifests}" "{work}" false && deploy_binary_install_prepared snell "{work}" "{active}" false
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=env,check=False)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertTrue(active.is_file())
   self.assertIn('protocol=snell',result.stdout)
   self.assertIn('stability=stable',result.stdout)
   self.assertIn('platform=linux-amd64',result.stdout)
   self.assertEqual(oct(active.stat().st_mode & 0o777),'0o700')

 def test_dry_run_does_not_create_work_directory(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); manifests=root/'manifests'; manifests.mkdir(); manifests.joinpath('snell-amd64.txt').write_text('v1.2.3|stable|2026-01-01|linux-amd64|snell|https://example.test/snell|'+'a'*64+'|raw|snell-server\n',encoding='utf-8')
   work=root/'work'
   result=subprocess.run(['bash','-c',f'source "{ORCHESTRATOR}"; deploy_binary_prepare_pinned snell "{manifests}" "{work}" true'],text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertFalse(work.exists())

 def test_metadata_failure_discards_the_prepared_candidate(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); manifests=root/'manifests'; manifests.mkdir(); payload=b'#!/usr/bin/env bash\nexit 0\n'; checksum=hashlib.sha256(payload).hexdigest()
   manifests.joinpath('snell-amd64.txt').write_text(f'v1.2.3|stable|2026-01-01|linux-amd64|snell|https://example.test/snell|{checksum}|raw|snell-server\n',encoding='utf-8')
   curl=root/'curl'; curl.write_text('#!/usr/bin/env bash\nfor arg in "$@"; do [ "$previous" = --output ] && printf "#!/usr/bin/env bash\\nexit 0\\n" > "$arg"; previous="$arg"; done\n',encoding='utf-8'); curl.chmod(0o700)
   work=root/'work'
   body=f'''source "{ORCHESTRATOR}"
binary_write_metadata() {{ return 1; }}
deploy_binary_prepare_pinned snell "{manifests}" "{work}" false
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,CURL_BIN=str(curl)),check=False)
   work_exists=work.exists()
  self.assertNotEqual(result.returncode,0)
  self.assertFalse(work_exists)

if __name__=='__main__': unittest.main()
