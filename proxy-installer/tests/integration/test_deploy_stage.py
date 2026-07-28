import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; STAGE=ROOT/'lib'/'orchestrators'/'deploy_stage.sh'; TOOL=ROOT/'tools'/'config_tool.py'
class DeployStageTests(unittest.TestCase):
 def test_stage_builds_private_material_and_descriptors_without_network(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t); config=p/'config.yaml'; subprocess.run(['python3',str(TOOL),'--config',str(config),'init'],check=True,capture_output=True)
   env=dict(os.environ,PYTHONPATH=str(ROOT.parent/'.python-packages'))
   subprocess.run(['bash',str(ROOT/'bin/proxy-installer.sh'),'--configure-snell','443','StagePass88','domain','node.example.com'],env=dict(env,PROXY_INSTALLER_CONFIG=str(config)),check=True,capture_output=True)
   work=p/'work'; body=f'''source "{STAGE}"
deploy_binary_prepare_pinned() {{ mkdir -p "$3"; printf '#!/usr/bin/env bash\\nexit 0\\n' > "$3/candidate"; chmod 700 "$3/candidate"; binary_write_metadata "$3/metadata" snell-server v5.0.1 beta 2026-06-12 linux-amd64 https://example.test/snell {'a'*64} false; }}
deploy_stage_prepare "{config}" "{p}/manifests" "{work}" /runtime /binary /certs /units /backup
'''
   result=subprocess.run(['bash','-c',body],env=env,text=True,capture_output=True,check=False)
   binaries=(work/'binaries.descriptor').read_text(); services=(work/'services.descriptor').read_text()
   entries_exists=(work/'surge.entries').exists()
   self.assertEqual(result.returncode,0,result.stderr); self.assertIn('stage=prepared',result.stdout)
   self.assertIn('snell|',binaries); self.assertIn('snell|',services); self.assertTrue(entries_exists)
if __name__=='__main__': unittest.main()
