import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HEALTH=ROOT/'lib'/'orchestrators'/'deploy_health.sh'
CLI=ROOT/'bin'/'proxy-installer.sh'
TOOL=ROOT/'tools'/'config_tool.py'

class DeployHealthTests(unittest.TestCase):
 def prepare_case(self, root):
  env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
  config=root/'config.yaml'
  subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,check=True,capture_output=True)
  commands=[
   ['--configure-snell','443','SnellPass88Secure','domain','node.example.com'],
   ['--configure-anytls','8443','AnyTlsPass88','node.example.com','true','false'],
   ['--configure-hysteria2','9000','Hy2Pass888','node.example.com','20000-20100','10','true','GeckoPass88','100'],
  ]
  for command in commands:
   subprocess.run(['bash',str(CLI),*command],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
  binary_dir=root/'bin'; binary_dir.mkdir()
  for name in ('snell-server','sing-box','hysteria'):
   path=binary_dir/name; path.write_text('#!/usr/bin/env bash\nexit 0\n'); path.chmod(0o700)
  calls=root/'systemctl-calls'; systemctl=root/'systemctl'
  systemctl.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$SYSTEMCTL_CALLS"\n[ "${FAIL_UNIT:-}" = "$3" ] && exit 1\nexit 0\n'); systemctl.chmod(0o700)
  ss=root/'ss'; ss.write_text('#!/usr/bin/env bash\ncase "$1" in -ltn) printf "x x x 0.0.0.0:443\\nx x x 0.0.0.0:8443\\n";; -lun) [ "${OMIT_UDP:-false}" = true ] || printf "x x x 0.0.0.0:9000\\n";; esac\n'); ss.chmod(0o700)
  nft=root/'nft'; nft.write_text('#!/usr/bin/env bash\n[ "${NFT_FAIL:-false}" = false ]\n'); nft.chmod(0o700)
  return config,binary_dir,dict(env,SYSTEMCTL_BIN=str(systemctl),SYSTEMCTL_CALLS=str(calls),SS_BIN=str(ss),NFT_BIN=str(nft)),calls

 def run_case(self, extra_env=None):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,binary_dir,env,calls=self.prepare_case(root)
   env.update(extra_env or {})
   body=f'''source "{HEALTH}"
deploy_health_verify_all "{config}" "{binary_dir}" 0
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   return result,calls.read_text().splitlines() if calls.exists() else []

 def test_all_protocols_and_port_hopping_pass(self):
  result,calls=self.run_case()
  self.assertEqual(result.returncode,0,result.stderr)
  for protocol in ('snell','anytls','hysteria2','hysteria2-port-hopping'):
   self.assertIn(f'health={protocol}:passed',result.stdout)
  self.assertIn('is-active --quiet proxy-installer-hysteria2-port-hop.service',calls)

 def test_listener_failure_reports_protocol_and_checks_remaining_services(self):
  result,calls=self.run_case({'OMIT_UDP':'true'})
  self.assertNotEqual(result.returncode,0)
  self.assertIn('health=hysteria2:failed',result.stderr)
  self.assertIn('health=snell:passed',result.stdout); self.assertIn('health=anytls:passed',result.stdout)
  self.assertTrue(any('proxy-installer-hysteria2.service' in call for call in calls))

 def test_missing_port_hopping_table_fails_complete_health_check(self):
  result,_=self.run_case({'NFT_FAIL':'true'})
  self.assertNotEqual(result.returncode,0)
  self.assertIn('health=hysteria2:passed',result.stdout)
  self.assertIn('health=hysteria2-port-hopping:failed',result.stderr)

if __name__=='__main__': unittest.main()
