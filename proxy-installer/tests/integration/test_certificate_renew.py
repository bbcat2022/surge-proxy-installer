import json, os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RENEW=ROOT/'lib'/'orchestrators'/'certificate_renew.sh'
CLI=ROOT/'bin'/'proxy-installer.sh'
TOOL=ROOT/'tools'/'config_tool.py'

class CertificateRenewTests(unittest.TestCase):
 def initialize(self, root, configure=True):
  config=root/'config.yaml'; env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
  subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,check=True,capture_output=True)
  if configure:
   subprocess.run(
    ['bash',str(CLI),'--configure-anytls','8443','AnyTlsPass88','node.example.com','true','false'],
    env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True
   )
  return config,env

 def test_empty_configuration_makes_scheduled_check_a_successful_noop(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.initialize(root,False)
   body=f'''source "{RENEW}"
certificate_renew_execute "{config}" "{root}/binary" "{root}/certificates" "{root}/state" certificate-empty 0
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('certificate-renewal=not-required',result.stdout)

 def test_changed_certificate_is_activated_and_service_health_is_checked(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.initialize(root)
   active=root/'certificates'; active.mkdir()
   (active/'cert.pem').write_text('old-cert'); (active/'key.pem').write_text('old-key')
   binary=root/'binary'; binary.mkdir()
   sing_box=binary/'sing-box'; sing_box.write_text('#!/usr/bin/env bash\necho v1.2.3\n'); sing_box.chmod(0o700)
   acme=root/'acme'
   acme.write_text(
    '#!/usr/bin/env bash\n'
    'if [ "$1" = --install-cert ]; then while [ "$#" -gt 0 ]; do '
    'case "$1" in --fullchain-file) shift; printf new-cert > "$1";; '
    '--key-file) shift; printf new-key > "$1";; esac; shift; done; fi\n'
   ); acme.chmod(0o700)
   openssl=root/'openssl'
   openssl.write_text('#!/usr/bin/env bash\ncase "$*" in *-pubkey*|*-pubout*) echo same-key;; esac\n'); openssl.chmod(0o700)
   systemctl=root/'systemctl'
   systemctl.write_text(
    '#!/usr/bin/env bash\n'
    '[ "$1" = is-active ] && { echo active; exit 0; }\n'
    '[ "$1" = is-enabled ] && { echo enabled; exit 0; }\n'
    'exit 0\n'
   ); systemctl.chmod(0o700)
   ss=root/'ss'
   ss.write_text('#!/usr/bin/env bash\nprintf "State Recv-Q Send-Q Local Address:Port\\nLISTEN 0 4096 0.0.0.0:8443\\n"\n'); ss.chmod(0o700)
   body=f'''source "{RENEW}"
certificate_renew_execute "{config}" "{binary}" "{active}" "{root}/state" certificate-new 0
'''
   run_env=dict(env,ACME_BIN=str(acme),OPENSSL_BIN=str(openssl),SYSTEMCTL_BIN=str(systemctl),SS_BIN=str(ss))
   result=subprocess.run(['bash','-c',body],env=run_env,text=True,capture_output=True,check=False)
   read=subprocess.run(['python3',str(TOOL),'--config',str(config),'read'],env=env,text=True,capture_output=True,check=True)
   data=json.loads(read.stdout)['data']
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertIn('certificate-renewal=success',result.stdout)
   self.assertEqual((active/'cert.pem').read_text(),'new-cert')
   self.assertEqual(data['history']['last_operation']['status'],'success')
   self.assertTrue((root/'state/transactions/certificate-new/config.yaml').is_file())
   self.assertTrue((root/'state/revisions/certificate-new/config.yaml').is_file())

 def test_unchanged_certificate_does_not_restart_service(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); config,env=self.initialize(root)
   active=root/'certificates'; active.mkdir()
   (active/'cert.pem').write_text('same-cert'); (active/'key.pem').write_text('same-key')
   acme=root/'acme'
   acme.write_text(
    '#!/usr/bin/env bash\n'
    'if [ "$1" = --install-cert ]; then while [ "$#" -gt 0 ]; do '
    'case "$1" in --fullchain-file) shift; printf same-cert > "$1";; '
    '--key-file) shift; printf same-key > "$1";; esac; shift; done; fi\n'
   ); acme.chmod(0o700)
   openssl=root/'openssl'
   openssl.write_text('#!/usr/bin/env bash\ncase "$*" in *-pubkey*|*-pubout*) echo matching-key;; esac\n'); openssl.chmod(0o700)
   systemctl_calls=root/'systemctl-calls'; systemctl=root/'systemctl'
   systemctl.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$SYSTEMCTL_CALLS"\nexit 1\n'); systemctl.chmod(0o700)
   body=f'''source "{RENEW}"
certificate_renew_execute "{config}" "{root}/binary" "{active}" "{root}/state" certificate-same 0
'''
   run_env=dict(env,ACME_BIN=str(acme),OPENSSL_BIN=str(openssl),SYSTEMCTL_BIN=str(systemctl),SYSTEMCTL_CALLS=str(systemctl_calls))
   result=subprocess.run(['bash','-c',body],env=run_env,text=True,capture_output=True,check=False)
   systemctl_was_called=systemctl_calls.exists()
   operation_work_exists=(root/'state/work/certificate-same').exists()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('certificate-renewal=not-due',result.stdout)
  self.assertFalse(systemctl_was_called)
  self.assertFalse(operation_work_exists)

if __name__=='__main__': unittest.main()
