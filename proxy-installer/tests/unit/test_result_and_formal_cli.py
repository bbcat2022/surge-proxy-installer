import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RESULT=ROOT/'lib'/'core'/'result.sh'; CLI=ROOT/'bin'/'proxy-installer.sh'
class ResultAndFormalCliTests(unittest.TestCase):
 def test_result_statuses_are_explicit(self):
  r=subprocess.run(['bash','-c',f'source "{RESULT}"; result_render partial-success "server ok" op-1'],text=True,capture_output=True,check=False)
  self.assertEqual(r.returncode,0); self.assertIn('next=check-client-export-or-history',r.stdout)
 def test_formal_cli_can_exit_without_system_change(self):
  with tempfile.TemporaryDirectory() as t:
   release=Path(t)/'os-release'; release.write_text('ID=debian\nVERSION_ID=13\n')
   env=dict(os.environ,ENV_EUID='0',ENV_OS_RELEASE=str(release),ENV_ARCH='x86_64',ENV_INIT='systemd')
   r=subprocess.run(['bash',str(CLI)],input='5\n',text=True,capture_output=True,env=env,check=False)
  self.assertEqual(r.returncode,0); self.assertIn('status=skipped',r.stdout)
 def test_formal_cli_exposes_a_non_mutating_deployment_preview(self):
  r=subprocess.run(['bash',str(CLI),'--plan-deploy','snell,hysteria2','443','8443','9000','20000-20100'],text=True,capture_output=True,check=False)
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertIn('operation=deploy',r.stdout)
  self.assertIn('confirmation=required',r.stdout)
 def test_deploy_preflight_reads_config_without_exposing_credentials(self):
  with tempfile.TemporaryDirectory() as t:
   config=Path(t)/'config.yaml'; release=Path(t)/'os-release'; release.write_text('ID=debian\nVERSION_ID=13\n')
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config),ENV_EUID='0',ENV_OS_RELEASE=str(release),ENV_ARCH='x86_64',ENV_INIT='systemd')
   tool=ROOT/'tools'/'config_tool.py'
   subprocess.run(['python3',str(tool),'--config',str(config),'init'],text=True,capture_output=True,env=env,check=True)
   command=['bash',str(CLI),'--configure-snell','443','SnellPass88','domain','node.example.com']
   self.assertEqual(subprocess.run(command,text=True,capture_output=True,env=env,check=False).returncode,0)
   r=subprocess.run(['bash',str(CLI),'--deploy-preflight'],text=True,capture_output=True,env=env,check=False)
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertIn('operation=deploy-preflight',r.stdout); self.assertIn('node.example.com',r.stdout)
  self.assertNotIn('SnellPass88',r.stdout)
 def test_status_uses_configured_state_path_and_redacts_secrets(self):
  with tempfile.TemporaryDirectory() as t:
   config=Path(t)/'config.yaml'
   tool=ROOT/'tools'/'config_tool.py'
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config))
   subprocess.run(['python3',str(tool),'--config',str(config),'init'],text=True,capture_output=True,env=env,check=True)
   subprocess.run(['python3',str(tool),'--config',str(config),'patch','--patch','{"desired":{"snell":{"psk":"private"}}}'],text=True,capture_output=True,env=env,check=True)
   r=subprocess.run(['bash',str(CLI),'--status'],text=True,capture_output=True,env=env,check=False)
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertIn('***REDACTED***',r.stdout)
 def test_configure_commands_persist_all_protocol_desired_state(self):
  with tempfile.TemporaryDirectory() as t:
   config=Path(t)/'config.yaml'; tool=ROOT/'tools'/'config_tool.py'
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config))
   subprocess.run(['python3',str(tool),'--config',str(config),'init'],text=True,capture_output=True,env=env,check=True)
   commands=[
    ['--configure-snell','443','SnellPass88','domain','node.example.com'],
    ['--configure-anytls','8443','AnyTlsPass88','node.example.com','true','false'],
    ['--configure-hysteria2','9000','Hy2Pass888','node.example.com','20000-20100','10','true','GeckoPass88','100'],
   ]
   for command in commands:
    result=subprocess.run(['bash',str(CLI),*command],text=True,capture_output=True,env=env,check=False)
    self.assertEqual(result.returncode,0,result.stderr)
   status=subprocess.run(['bash',str(CLI),'--status'],text=True,capture_output=True,env=env,check=False)
  self.assertEqual(status.returncode,0,status.stderr)
  self.assertIn('\"snell\"',status.stdout); self.assertIn('\"anytls\"',status.stdout); self.assertIn('\"hysteria2\"',status.stdout)
  self.assertIn('***REDACTED***',status.stdout)
 def test_binary_candidates_are_fixed_and_protocol_specific(self):
  snell=subprocess.run(['bash',str(CLI),'--binary-candidates','snell'],text=True,capture_output=True,check=False)
  anytls=subprocess.run(['bash',str(CLI),'--binary-candidates','anytls'],text=True,capture_output=True,check=False)
  hy2=subprocess.run(['bash',str(CLI),'--binary-candidates','hysteria2'],text=True,capture_output=True,check=False)
  self.assertEqual(snell.returncode,0,snell.stderr); self.assertIn('protocol=snell-v6-beta',snell.stdout); self.assertIn('server-artifact=v5.0.1',snell.stdout)
  self.assertEqual(anytls.returncode,0,anytls.stderr); self.assertIn('v1.13.14',anytls.stdout)
  self.assertEqual(hy2.returncode,0,hy2.stderr); self.assertIn('v2.10.0',hy2.stdout)
 def test_certificate_renew_command_uses_installed_paths(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config=root/'config.yaml'; calls=root/'calls'; executor=root/'renew'
   executor.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" > "$RENEW_CALLS"\n'); executor.chmod(0o700)
   env=dict(
    os.environ,PROXY_INSTALLER_CONFIG=str(config),CERTIFICATE_RENEW_EXECUTOR=str(executor),
    PROXY_INSTALLER_OPERATION_ID='certificate-test',RENEW_CALLS=str(calls)
   )
   result=subprocess.run(['bash',str(CLI),'--renew-certificate'],env=env,text=True,capture_output=True,check=False)
   arguments=calls.read_text().split()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(arguments[0],str(config))
  self.assertEqual(arguments[1:],[('/opt/proxy-installer/bin'),('/etc/proxy-installer/certificates'),('/var/lib/proxy-installer'),'certificate-test','20'])
 def test_interactive_menu_configures_all_protocols_and_starts_deployment(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config=root/'config.yaml'; release=root/'os-release'; calls=root/'deploy-calls'; executor=root/'deploy'
   release.write_text('ID=debian\nVERSION_ID=13\n')
   executor.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" > "$DEPLOY_CALLS"\n'); executor.chmod(0o700)
   env=dict(
    os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config),
    ENV_EUID='0',ENV_OS_RELEASE=str(release),ENV_ARCH='x86_64',ENV_INIT='systemd',
    DEPLOY_ENVIRONMENT_EXECUTOR='/usr/bin/true',DEPLOY_TOOL_CHECK_EXECUTOR='/usr/bin/true',
    DEPLOY_VALIDATE_EXECUTOR='/usr/bin/true',DEPLOY_RUN_EXECUTOR=str(executor),DEPLOY_CALLS=str(calls),
    PROXY_INSTALLER_OPERATION_ID='interactive-deploy',PROXY_INSTALLER_RUNTIME_DIR=str(root/'runtime'),
    PROXY_INSTALLER_BINARY_DIR=str(root/'binary'),PROXY_INSTALLER_CERTIFICATE_DIR=str(root/'certificates'),
    PROXY_INSTALLER_UNIT_DIR=str(root/'units'),PROXY_INSTALLER_STATE_ROOT=str(root/'state'),
    PROXY_INSTALLER_EXPORT_TARGET=str(root/'surge.conf'),
   )
   subprocess.run(['python3',str(ROOT/'tools/config_tool.py'),'--config',str(config),'init'],env=env,check=True,capture_output=True)
   answers='\n'.join((
    '1','1,2,3','198.51.100.9','node.example.com','443','SnellPass88','8443','AnyTlsPass88',
    '9000','Hy2Pass888','','20000-20100','30','','GeckoPass88','100','DEPLOY','','5',''
   ))
   result=subprocess.run(['bash',str(CLI)],input=answers,env=env,text=True,capture_output=True,check=False)
   status=subprocess.run(['bash',str(CLI),'--status'],env=env,text=True,capture_output=True,check=True)
   deploy_arguments=calls.read_text()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('interactive-deploy',deploy_arguments)
  self.assertIn('198.51.100.9',deploy_arguments)
  self.assertIn('"snell"',status.stdout); self.assertIn('"anytls"',status.stdout); self.assertIn('"hysteria2"',status.stdout)
  self.assertIn('***REDACTED***',status.stdout)
 def test_interactive_hysteria_only_generates_passwords_and_can_disable_port_hopping(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config=root/'config.yaml'; release=root/'os-release'; calls=root/'deploy-calls'; executor=root/'deploy'
   generator=root/'generator'; counter=root/'counter'
   release.write_text('ID=debian\nVERSION_ID=13\n')
   executor.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" > "$DEPLOY_CALLS"\n'); executor.chmod(0o700)
   generator.write_text(
    '#!/usr/bin/env bash\n'
    'count=0\n'
    '[ ! -f "$PASSWORD_COUNTER" ] || IFS= read -r count < "$PASSWORD_COUNTER"\n'
    'count=$((count + 1)); printf "%s" "$count" > "$PASSWORD_COUNTER"\n'
    'printf "GeneratedPass%02d\\n" "$count"\n'
   ); generator.chmod(0o700)
   env=dict(
    os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'),PROXY_INSTALLER_CONFIG=str(config),
    ENV_EUID='0',ENV_OS_RELEASE=str(release),ENV_ARCH='x86_64',ENV_INIT='systemd',
    DEPLOY_ENVIRONMENT_EXECUTOR='/usr/bin/true',DEPLOY_TOOL_CHECK_EXECUTOR='/usr/bin/true',
    DEPLOY_VALIDATE_EXECUTOR='/usr/bin/true',DEPLOY_RUN_EXECUTOR=str(executor),DEPLOY_CALLS=str(calls),
    PROXY_INSTALLER_PASSWORD_GENERATOR=str(generator),PASSWORD_COUNTER=str(counter),
    PROXY_INSTALLER_OPERATION_ID='hysteria-only',PROXY_INSTALLER_RUNTIME_DIR=str(root/'runtime'),
    PROXY_INSTALLER_BINARY_DIR=str(root/'binary'),PROXY_INSTALLER_CERTIFICATE_DIR=str(root/'certificates'),
    PROXY_INSTALLER_UNIT_DIR=str(root/'units'),PROXY_INSTALLER_STATE_ROOT=str(root/'state'),
    PROXY_INSTALLER_EXPORT_TARGET=str(root/'surge.conf'),
   )
   subprocess.run(['python3',str(ROOT/'tools/config_tool.py'),'--config',str(config),'init'],env=env,check=True,capture_output=True)
   answers='\n'.join(('1','3','198.51.100.9','node.example.com','','','n','','','','DEPLOY','','5',''))
   result=subprocess.run(['bash',str(CLI)],input=answers,env=env,text=True,capture_output=True,check=False)
   deployment_env=subprocess.run(
    ['python3',str(ROOT/'tools/config_tool.py'),'--config',str(config),'deployment-env'],
    env=env,text=True,capture_output=True,check=True
   ).stdout
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('DEPLOY_SELECTED_PROTOCOLS=hysteria2',deployment_env)
  self.assertIn('HYSTERIA2_PASSWORD=GeneratedPass01',deployment_env)
  self.assertIn('HYSTERIA2_GECKO_PASSWORD=GeneratedPass02',deployment_env)
  self.assertIn("HYSTERIA2_PORT_HOPPING_RANGE=''",deployment_env)
  self.assertIn('HYSTERIA2_HOP_INTERVAL=30',deployment_env)
if __name__=='__main__': unittest.main()
