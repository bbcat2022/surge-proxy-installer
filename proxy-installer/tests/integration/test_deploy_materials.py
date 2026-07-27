import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CLI=ROOT/'bin'/'proxy-installer.sh'; TOOL=ROOT/'tools'/'config_tool.py'

class DeployMaterialsTests(unittest.TestCase):
 def test_prepares_all_enabled_protocol_candidates_without_system_paths(self):
  with tempfile.TemporaryDirectory() as t:
   base=Path(t); config=base/'config.yaml'; candidate=base/'candidate'; runtime=base/'runtime'; binary=base/'binary'; cert=base/'cert'
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config))
   subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,text=True,capture_output=True,check=True)
   commands=[
    ['--configure-snell','443','SnellPass88','domain','node.example.com'],
    ['--configure-anytls','8443','AnyTlsPass88','node.example.com','true','false'],
    ['--configure-hysteria2','9000','Hy2Pass888','node.example.com','20000-20100','10','true','GeckoPass88','100'],
   ]
   for command in commands:
    result=subprocess.run(['bash',str(CLI),*command],env=env,text=True,capture_output=True,check=False)
    self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run(['bash',str(CLI),'--prepare-deploy',str(candidate),str(runtime),str(binary),str(cert)],env=env,text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertIn('protocols=snell,anytls,hysteria2',result.stdout)
   self.assertTrue((candidate/'snell.conf').is_file())
   self.assertTrue((candidate/'anytls.json').is_file())
   self.assertTrue((candidate/'hysteria2.yaml').is_file())
   self.assertTrue((candidate/'proxy-installer-snell.service').is_file())
   self.assertIn('minPacketSize: 512',(candidate/'hysteria2.yaml').read_text())
   self.assertIn('maxPacketSize: 1200',(candidate/'hysteria2.yaml').read_text())
   self.assertEqual(oct((candidate/'anytls.json').stat().st_mode & 0o777), '0o600')

if __name__=='__main__': unittest.main()
