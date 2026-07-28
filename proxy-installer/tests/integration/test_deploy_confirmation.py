import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; CLI=ROOT/'bin'/'proxy-installer.sh'
class DeployConfirmationTests(unittest.TestCase):
 def test_deploy_refuses_without_explicit_confirmation_before_environment_access(self):
  result=subprocess.run(['bash',str(CLI),'--deploy','198.51.100.9','no'],text=True,capture_output=True,env=os.environ,check=False)
  self.assertNotEqual(result.returncode,0); self.assertIn('confirmation=required',result.stdout)
 def test_deploy_rejects_invalid_ipv4_before_environment_access(self):
  result=subprocess.run(['bash',str(CLI),'--deploy','999.1.1.1','--confirm'],text=True,capture_output=True,env=os.environ,check=False)
  self.assertNotEqual(result.returncode,0); self.assertNotIn('failed=root-required',result.stdout)
 def test_confirmed_deploy_reaches_top_level_executor_with_standard_paths(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); calls=root/'calls'
   ok=root/'ok'; ok.write_text('#!/usr/bin/env bash\nexit 0\n'); ok.chmod(0o700)
   run=root/'run'
   run.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" > "$DEPLOY_CALLS"\n'); run.chmod(0o700)
   env=dict(
    os.environ,DEPLOY_ENVIRONMENT_EXECUTOR=str(ok),DEPLOY_TOOL_CHECK_EXECUTOR=str(ok),
    DEPLOY_VALIDATE_EXECUTOR=str(ok),DEPLOY_RUN_EXECUTOR=str(run),DEPLOY_CALLS=str(calls),
    PROXY_INSTALLER_CONFIG=str(root/'config.yaml'),PROXY_INSTALLER_OPERATION_ID='deploy-test',
    PROXY_INSTALLER_RUNTIME_DIR=str(root/'runtime'),PROXY_INSTALLER_BINARY_DIR=str(root/'binary'),
    PROXY_INSTALLER_CERTIFICATE_DIR=str(root/'certificates'),PROXY_INSTALLER_UNIT_DIR=str(root/'units'),
    PROXY_INSTALLER_STATE_ROOT=str(root/'state'),PROXY_INSTALLER_EXPORT_TARGET=str(root/'export/surge.conf')
   )
   result=subprocess.run(['bash',str(CLI),'--deploy','198.51.100.9','--confirm'],text=True,capture_output=True,env=env,check=False)
   arguments=calls.read_text()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('deploy-test',arguments); self.assertIn('198.51.100.9',arguments)
  self.assertIn('auto ufw',arguments)
if __name__=='__main__': unittest.main()
