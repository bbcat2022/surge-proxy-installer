import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; CLI=ROOT/'bin'/'proxy-installer.sh'
class DeployConfirmationTests(unittest.TestCase):
 def test_deploy_refuses_without_explicit_confirmation_before_environment_access(self):
  result=subprocess.run(['bash',str(CLI),'--deploy','198.51.100.9','no'],text=True,capture_output=True,env=os.environ,check=False)
  self.assertNotEqual(result.returncode,0); self.assertIn('confirmation=required',result.stdout)
if __name__=='__main__': unittest.main()
