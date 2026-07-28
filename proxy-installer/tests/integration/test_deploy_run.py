import hashlib, json, os, subprocess, tempfile, unittest
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

 def test_snell_deploy_runs_from_config_through_health_and_export(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.prepare_config(root)
   payload=b'#!/usr/bin/env bash\necho v1.2.3\n'; checksum=hashlib.sha256(payload).hexdigest()
   manifests=root/'manifests'; manifests.mkdir()
   manifests.joinpath('snell-amd64.txt').write_text(f'v1.2.3|stable|2026-01-01|linux-amd64|snell|https://example.test/snell|{checksum}|raw|snell-server\n')
   curl=root/'curl'
   curl.write_text('#!/usr/bin/env bash\nfor arg in "$@"; do [ "${previous:-}" = --output ] && printf "#!/usr/bin/env bash\\necho v1.2.3\\n" > "$arg"; previous="$arg"; done\n'); curl.chmod(0o700)
   active_state=root/'active-state'; enabled_state=root/'enabled-state'; systemctl=root/'systemctl'
   systemctl.write_text(
    '#!/usr/bin/env bash\n'
    'case "$1" in\n'
    ' is-active) [ -f "$ACTIVE_STATE" ] && { printf "active\\n"; exit 0; }; printf "inactive\\n"; exit 3;;\n'
    ' is-enabled) [ -f "$ENABLED_STATE" ] && { printf "enabled\\n"; exit 0; }; printf "disabled\\n"; exit 1;;\n'
    ' restart|start) touch "$ACTIVE_STATE";;\n'
    ' stop) rm -f "$ACTIVE_STATE";;\n'
    ' enable) touch "$ENABLED_STATE";;\n'
    ' disable) rm -f "$ENABLED_STATE";;\n'
    'esac\n'
   ); systemctl.chmod(0o700)
   ss=root/'ss'; ss.write_text('#!/usr/bin/env bash\nprintf "x x x 0.0.0.0:443\\n"\n'); ss.chmod(0o700)
   paths={name:root/name for name in ('runtime','binary','certificates','units','state')}
   export=root/'export/surge.conf'
   body=f'''source "{RUN}"
deploy_run_execute "{config}" 198.51.100.9 "{manifests}" deploy-full "{paths['runtime']}" "{paths['binary']}" "{paths['certificates']}" "{paths['units']}" "{paths['state']}" "{export}" manual manual
'''
   run_env=dict(env,CURL_BIN=str(curl),SYSTEMCTL_BIN=str(systemctl),SS_BIN=str(ss),ACTIVE_STATE=str(active_state),ENABLED_STATE=str(enabled_state),DEPLOY_RUN_LOG_LINES='0')
   result=subprocess.run(['bash','-c',body],env=run_env,text=True,capture_output=True,check=False)
   read=subprocess.run(['python3',str(TOOL),'--config',str(config),'read'],env=env,text=True,capture_output=True,check=True)
   data=json.loads(read.stdout)['data']
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertIn('deployment-result=success',result.stdout)
   self.assertTrue((paths['binary']/'snell-server').is_file())
   self.assertTrue((paths['runtime']/'snell.conf').is_file())
   self.assertTrue((paths['units']/'proxy-installer-snell.service').is_file())
   self.assertIn('[Proxy]',export.read_text()); self.assertEqual(data['applied']['operation_id'],'deploy-full')

if __name__=='__main__': unittest.main()
