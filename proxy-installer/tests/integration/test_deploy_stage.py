import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; STAGE=ROOT/'lib'/'orchestrators'/'deploy_stage.sh'; TOOL=ROOT/'tools'/'config_tool.py'
class DeployStageTests(unittest.TestCase):
 def initialize_config(self, directory):
  config=directory/'config.yaml'
  env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
  subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],env=env,check=True,capture_output=True)
  return config

 def binary_stub(self):
  return f'''deploy_binary_prepare_pinned() {{ local binary_id; binary_id="$(protocol_registry_get "$1" binary_id)" || return 1; mkdir -p "$3"; printf '#!/usr/bin/env bash\\nexit 0\\n' > "$3/candidate"; chmod 700 "$3/candidate"; binary_write_metadata "$3/metadata" "$binary_id" v1.0.0 stable 2026-01-01 linux-amd64 https://example.test/"$1" {'a'*64} false; }}
'''

 def test_stage_builds_private_material_and_descriptors_without_network(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); config=self.initialize_config(p)
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
   subprocess.run(['bash',str(ROOT/'bin/proxy-installer.sh'),'--configure-snell','443','StagePass88','domain','node.example.com'],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
   work=p/'work'; body=f'''source "{STAGE}"
{self.binary_stub()}
deploy_stage_prepare "{config}" "{p}/manifests" "{work}" /runtime /binary /certs /units /backup
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   binaries=(work/'binaries.descriptor').read_text(); services=(work/'services.descriptor').read_text(); firewall=(work/'firewall.descriptor').read_text()
   entries_exists=(work/'surge.entries').exists()
   self.assertEqual(result.returncode,0,result.stderr); self.assertIn('stage=prepared',result.stdout)
   self.assertIn('snell|',binaries); self.assertIn('snell|',services); self.assertTrue(entries_exists)
   self.assertEqual(firewall,'schema=1\nrule=tcp:443\n')
   self.assertEqual(oct((work/'firewall.descriptor').stat().st_mode & 0o777),'0o600')

 def test_complete_stage_prepares_tls_certificate_for_service_install(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); config=self.initialize_config(p); env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
   subprocess.run(['bash',str(ROOT/'bin/proxy-installer.sh'),'--configure-anytls','8443','AnyTlsPass88','node.example.com','true','false'],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
   work=p/'work'; body=f'''source "{STAGE}"
{self.binary_stub()}
deploy_certificates_prepare_candidates() {{ mkdir -p "$3/node.example.com"; printf cert > "$3/node.example.com/cert.pem"; printf key > "$3/node.example.com/key.pem"; }}
deploy_stage_prepare_complete "{config}" 198.51.100.9 "{p}/manifests" "{work}" /runtime /binary /certs /units /backup || exit $?
printf 'CERT=%s\\nKEY=%s\\nACTIVE=%s\\nSNAPSHOT=%s\\n' "$DEPLOY_CERTIFICATE_CANDIDATE_CERT" "$DEPLOY_CERTIFICATE_CANDIDATE_KEY" "$DEPLOY_CERTIFICATE_ACTIVE_DIR" "$DEPLOY_CERTIFICATE_SNAPSHOT_DIR"
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr); self.assertIn('stage-certificate=prepared',result.stdout)
   self.assertIn(f'CERT={work}/certificates/node.example.com/cert.pem',result.stdout)
   self.assertIn(f'KEY={work}/certificates/node.example.com/key.pem',result.stdout)
   self.assertIn('ACTIVE=/certs',result.stdout); self.assertIn('SNAPSHOT=/backup/certificate',result.stdout)
   self.assertTrue((work/'services.descriptor').is_file())

 def test_complete_stage_skips_certificate_for_snell_only(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); config=self.initialize_config(p); env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
   subprocess.run(['bash',str(ROOT/'bin/proxy-installer.sh'),'--configure-snell','443','StagePass88','domain','node.example.com'],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
   work=p/'work'; body=f'''source "{STAGE}"
{self.binary_stub()}
deploy_certificates_prepare_candidates() {{ return 0; }}
deploy_stage_prepare_complete "{config}" 198.51.100.9 "{p}/manifests" "{work}" /runtime /binary /certs /units /backup || exit $?
printf 'CERT=%s\\n' "${{DEPLOY_CERTIFICATE_CANDIDATE_CERT:-}}"
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,0,result.stderr); self.assertIn('stage-certificate=not-required',result.stdout)
   self.assertIn('CERT=\n',result.stdout)
if __name__=='__main__': unittest.main()
