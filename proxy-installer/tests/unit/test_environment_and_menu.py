import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
ENV=ROOT/'lib'/'core'/'environment.sh'; MENU=ROOT/'lib'/'interface'/'menu.sh'
class EnvironmentAndMenuTests(unittest.TestCase):
 def run_command(self,s,e,env=None):
  data=dict(os.environ); data.update(env or {})
  return subprocess.run(['bash','-c',f'source "{s}"; {e}'],text=True,capture_output=True,env=data,check=False)
 def test_target_environment_success_and_failure(self):
  with tempfile.TemporaryDirectory() as t:
   f=Path(t)/'os-release'; f.write_text('ID=debian\nVERSION_ID="13"\n')
   good=self.run_command(ENV,'environment_check',{'ENV_EUID':'0','ENV_OS_RELEASE':str(f),'ENV_ARCH':'x86_64','ENV_INIT':'systemd'})
   bad=self.run_command(ENV,'environment_check',{'ENV_EUID':'0','ENV_OS_RELEASE':str(f),'ENV_ARCH':'arm64','ENV_INIT':'systemd'})
  self.assertEqual(good.returncode,0); self.assertIn('success=environment-ready',good.stdout); self.assertNotEqual(bad.returncode,0)
 def test_deploy_tool_check_reports_missing_command(self):
  with tempfile.TemporaryDirectory() as t:
   tool=Path(t)/'tool'; tool.write_text('#!/usr/bin/env bash\nexit 0\n'); tool.chmod(0o700)
   variables={name:str(tool) for name in ('CURL_BIN','TAR_BIN','UNZIP_BIN','OPENSSL_BIN','SS_BIN','NFT_BIN','ACME_BIN','SYSTEMCTL_BIN')}
   good=self.run_command(ENV,'environment_check_deploy_tools',variables)
   bad=self.run_command(ENV,'environment_check_deploy_tools',dict(variables,ACME_BIN=str(Path(t)/'missing')))
  self.assertEqual(good.returncode,0,good.stderr); self.assertIn('success=deploy-tools-ready',good.stdout)
  self.assertNotEqual(bad.returncode,0); self.assertIn('missing-command:acme.sh',bad.stdout)
 def test_menu_choices_and_confirmations(self):
  rendered=self.run_command(MENU,'menu_render_main'); self.assertIn('1) 配置并部署代理服务',rendered.stdout)
  self.assertEqual(self.run_command(MENU,'menu_parse_main 3').stdout,'export')
  self.assertEqual(self.run_command(MENU,'menu_parse_main 4').stdout,'certificate')
  self.assertEqual(self.run_command(MENU,'menu_parse_protocol_selection "1,2,3"').stdout.strip(),'snell,anytls,hysteria2')
  self.assertEqual(self.run_command(MENU,'menu_parse_protocol_selection 4').stdout.strip(),'back')
  self.assertNotEqual(self.run_command(MENU,'menu_parse_protocol_selection "1,5"').returncode,0)
  self.assertEqual(self.run_command(MENU,'menu_confirm 1').returncode,0)
  self.assertNotEqual(self.run_command(MENU,'menu_confirm 2').returncode,0)
if __name__=='__main__': unittest.main()
