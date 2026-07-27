import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CLI=ROOT/'bin'/'proxy-installer.sh'; TOOL=ROOT/'tools'/'config_tool.py'

class DeployCertificatesTests(unittest.TestCase):
 def test_tls_domains_are_deduplicated_and_preflighted(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config=root/'config.yaml'; getent=root/'getent'; ss=root/'ss'
   getent.write_text('#!/usr/bin/env bash\nprintf "198.51.100.9 STREAM x\\n"\n',encoding='utf-8'); getent.chmod(0o700)
   ss.write_text('#!/usr/bin/env bash\nprintf "State Recv-Q Send-Q Local Address:Port Peer Address:Port\\n"\n',encoding='utf-8'); ss.chmod(0o700)
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config),GETENT_BIN=str(getent),SS_BIN=str(ss))
   subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,text=True,capture_output=True,check=True)
   for command in (["--configure-anytls","8443","AnyTlsPass88","node.example.com","true","false"],["--configure-hysteria2","9000","Hy2Pass888","node.example.com","","10","false","","100"]):
    result=subprocess.run(['bash',str(CLI),*command],env=env,text=True,capture_output=True,check=False); self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run(['bash',str(CLI),'--certificate-preflight','198.51.100.9'],env=env,text=True,capture_output=True,check=False)
  self.assertEqual(result.returncode,0,result.stderr); self.assertEqual(result.stdout.count('dns-domain=node.example.com'),1); self.assertIn('certificate-preflight=passed',result.stdout)

if __name__=='__main__': unittest.main()
