import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "bin" / "dev.sh"

class DevCliSmokeTests(unittest.TestCase):
 def run_cli(self,*args): return subprocess.run(["bash",str(CLI),*args],text=True,capture_output=True,check=False)
 def test_init_config_and_plan_commands(self):
  with tempfile.TemporaryDirectory() as temp:
   config=str(Path(temp)/'config.yaml')
   init=self.run_cli('init-config',config)
   deploy=self.run_cli('plan-deploy','snell,anytls','443','8443','8444','')
   change=self.run_cli('plan-config','anytls','reuse')
  self.assertEqual(init.returncode,0,init.stderr)
  self.assertEqual(json.loads(init.stdout)['result'],'success')
  self.assertIn('certificate=shared-main-domain',deploy.stdout)
  self.assertIn('service-restart=false',change.stdout)
 def test_invalid_command_has_no_side_effect(self):
  result=self.run_cli('deploy-now')
  self.assertEqual(result.returncode,2)
  self.assertIn('Usage:',result.stdout)
if __name__=='__main__': unittest.main()
