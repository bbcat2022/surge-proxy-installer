import subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DESCRIPTOR=ROOT/'lib'/'orchestrators'/'deploy_binary_descriptor.sh'

class DeployBinaryDescriptorTests(unittest.TestCase):
 def test_builds_only_selected_verified_protocol_binaries(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); candidates=root/'candidates'; (candidates/'snell').mkdir(parents=True); (candidates/'hysteria2').mkdir()
   for candidate in (candidates/'snell'/'candidate', candidates/'hysteria2'/'candidate'):
    candidate.write_text('#!/usr/bin/env bash\n'); candidate.chmod(0o700)
   descriptor=root/'out'/'binaries'
   command=f'source "{DESCRIPTOR}"; deploy_binary_descriptor_build "{candidates}" /opt/proxy/bin /var/lib/proxy/backups "{descriptor}" snell,hysteria2'
   result=subprocess.run(['bash','-c',command],text=True,capture_output=True,check=False)
   content=descriptor.read_text()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('snell|',content); self.assertIn('/opt/proxy/bin/snell-server',content)
  self.assertIn('hysteria2|',content); self.assertIn('/opt/proxy/bin/hysteria',content)
  self.assertNotIn('anytls|',content)

 def test_refuses_missing_candidate_or_unknown_protocol(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); candidates=root/'candidates'; candidates.mkdir(); descriptor=root/'binaries'
   missing=subprocess.run(['bash','-c',f'source "{DESCRIPTOR}"; deploy_binary_descriptor_build "{candidates}" /opt/bin /var/lib/backup "{descriptor}" snell'],text=True,capture_output=True,check=False)
   unknown=subprocess.run(['bash','-c',f'source "{DESCRIPTOR}"; deploy_binary_descriptor_build "{candidates}" /opt/bin /var/lib/backup "{descriptor}" unknown'],text=True,capture_output=True,check=False)
  self.assertNotEqual(missing.returncode,0); self.assertNotEqual(unknown.returncode,0)

if __name__=='__main__': unittest.main()
