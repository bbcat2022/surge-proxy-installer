import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EXEC=ROOT/'lib'/'orchestrators'/'certificate_execute.sh'

class CertificateExecuteTests(unittest.TestCase):
 def run_case(self, health=True):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); openssl=p/'openssl'; systemctl=p/'systemctl'
   openssl.write_text('#!/usr/bin/env bash\nexit 0\n'); systemctl.write_text('#!/usr/bin/env bash\nexit 0\n')
   openssl.chmod(0o700); systemctl.chmod(0o700)
   candidate=p/'candidate'; snapshot_dir=p/'snapshot'; active=p/'active'; candidate.mkdir(); snapshot_dir.mkdir()
   for folder,label in ((candidate,'new'),(snapshot_dir,'old')):
    (folder/'cert.pem').write_text(label+' cert'); (folder/'key.pem').write_text(label+' key')
   body=f'''source "{EXEC}"
snapshot() {{ return 0; }}
health() {{ return {0 if health else 1}; }}
commit() {{ return 0; }}
export_cb() {{ return 0; }}
certificate_execute_install "{p/'lock'}" certificate-install "{candidate/'cert.pem'}" "{candidate/'key.pem'}" "{active}" "{snapshot_dir}" anytls.service,hysteria2.service snapshot health commit export_cb
code=$?
printf 'RESULT=%s' "$TX_RESULT"
exit "$code"'''
   r=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,OPENSSL_BIN=str(openssl),SYSTEMCTL_BIN=str(systemctl)))
   return r,(active/'cert.pem').read_text()
 def test_healthy_candidate_is_committed(self):
  r,certificate=self.run_case()
  self.assertEqual(r.returncode,0,r.stderr); self.assertIn('RESULT=success',r.stdout); self.assertEqual(certificate,'new cert')
 def test_health_failure_restores_previous_certificate(self):
  r,certificate=self.run_case(health=False)
  self.assertNotEqual(r.returncode,0); self.assertIn('RESULT=rollback-success',r.stdout); self.assertEqual(certificate,'old cert')

if __name__=='__main__': unittest.main()
