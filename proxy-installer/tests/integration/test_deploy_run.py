import json, os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'lib'/'orchestrators'/'deploy_run.sh'
TOOL=ROOT/'tools'/'config_tool.py'
CLI=ROOT/'bin'/'proxy-installer.sh'

class DeployRunTests(unittest.TestCase):
 def prepare_config(self, root):
  env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
  config=root/'config.yaml'
  subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,check=True,capture_output=True)
  subprocess.run(['bash',str(CLI),'--configure-snell','443','RunPass88','domain','node.example.com'],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
  return config,env

 def test_top_level_run_connects_stage_health_state_and_result_recording(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.prepare_config(root); calls=root/'calls'
   body=f'''source "{RUN}"
deploy_stage_prepare_complete() {{
  mkdir -p "$4"
  printf binary > "$4/binaries.descriptor"
  printf service > "$4/services.descriptor"
  printf entry > "$4/surge.entries"
  printf firewall > "$4/firewall.descriptor"
}}
deploy_health_verify_all() {{ printf health >> "{calls}"; }}
deploy_coordinator_execute_unified() {{
  printf '%s|%s|%s|%s\\n' "$DEPLOY_FIREWALL_MODE" "$DEPLOY_FIREWALL_TOOL" "$DEPLOY_FIREWALL_DESCRIPTOR" "$DEPLOY_FIREWALL_CONTEXT" >> "{calls}"
  "$7" || return 1
  "$8" || return 1
  "$9" || return 1
  "${{10}}" || return 1
  "$DEPLOY_COORDINATOR_RESULT_CALLBACK" "$2" success "" "operation completed and passed health verification" ""
}}
deploy_run_execute "{config}" 198.51.100.9 "{root}/manifests" deploy-1 "{root}/runtime" "{root}/binary" "{root}/certificates" "{root}/units" "{root}/state" "{root}/export/surge.conf" manual manual
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   read=subprocess.run(['python3',str(TOOL),'--config',str(config),'read'],env=env,text=True,capture_output=True,check=True)
   data=json.loads(read.stdout)['data']
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual(data['applied']['operation_id'],'deploy-1')
   self.assertEqual(data['history']['last_operation']['status'],'success')
   self.assertTrue((root/'state/transactions/deploy-1/config.yaml').is_file())
   self.assertTrue((root/'state/revisions/deploy-1/config.yaml').is_file())
   logged=calls.read_text()
   self.assertIn('health',logged); self.assertIn('manual|manual|',logged)

 def test_stage_failure_is_recorded_without_starting_install(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.prepare_config(root); marker=root/'install-called'
   body=f'''source "{RUN}"
deploy_stage_prepare_complete() {{ return 1; }}
deploy_coordinator_execute_unified() {{ touch "{marker}"; }}
deploy_run_execute "{config}" 198.51.100.9 "{root}/manifests" deploy-2 "{root}/runtime" "{root}/binary" "{root}/certificates" "{root}/units" "{root}/state" "{root}/export/surge.conf" manual manual
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   read=subprocess.run(['python3',str(TOOL),'--config',str(config),'read'],env=env,text=True,capture_output=True,check=True)
   operation=json.loads(read.stdout)['data']['history']['last_operation']
   self.assertNotEqual(result.returncode,0); self.assertFalse(marker.exists())
   self.assertEqual(operation['status'],'failed'); self.assertEqual(operation['failed_stage'],'preparation')

if __name__=='__main__': unittest.main()
