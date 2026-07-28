import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CLI=ROOT/'bin'/'proxy-installer.sh'; TOOL=ROOT/'tools'/'config_tool.py'

class DeployValidateTests(unittest.TestCase):
 def test_validate_deploy_runs_full_local_gate_without_retaining_materials(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config=root/'config.yaml'; release=root/'os-release'; release.write_text('ID=debian\nVERSION_ID=13\n')
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config),ENV_EUID='0',ENV_OS_RELEASE=str(release),ENV_ARCH='x86_64',ENV_INIT='systemd')
   subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,text=True,capture_output=True,check=True)
   configured=subprocess.run(['bash',str(CLI),'--configure-snell','443','SnellPass88Secure','domain','node.example.com'],env=env,text=True,capture_output=True,check=False)
   self.assertEqual(configured.returncode,0,configured.stderr)
   result=subprocess.run(['bash',str(CLI),'--validate-deploy','198.51.100.9'],env=env,text=True,capture_output=True,check=False)
  self.assertEqual(result.returncode,0,result.stderr); self.assertIn('binary-plan=snell:v6.0.0b4',result.stdout); self.assertIn('service-plan-count=1',result.stdout); self.assertIn('deploy-validation=passed',result.stdout)

if __name__=='__main__': unittest.main()
