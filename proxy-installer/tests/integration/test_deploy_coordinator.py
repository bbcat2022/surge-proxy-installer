import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
COORD=ROOT/'lib'/'orchestrators'/'deploy_coordinator.sh'

class DeployCoordinatorTests(unittest.TestCase):
 def test_service_failure_restores_already_installed_binary(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); mock=root/'systemctl'; mock.write_text('#!/usr/bin/env bash\nexit 0\n'); mock.chmod(0o700)
   work=root/'binary-work'; work.mkdir(); candidate=work/'candidate'; candidate.write_text('#!/usr/bin/env bash\necho v5.0.1\nexit 0\n'); candidate.chmod(0o700)
   (work/'metadata').write_text('binary_id=snell-server\nversion=v5.0.1\nstability=beta\nrelease_date=2026-06-12\nplatform=linux-amd64\nsource=https://example.test/snell\nsha256='+'a'*64+'\n')
   active=root/'snell'; active.write_text('old-binary'); active.chmod(0o700); active_metadata=root/'snell.metadata'; active_metadata.write_text('old-metadata')
   binary_desc=root/'binaries'; binary_desc.write_text(f'snell|{work}|{active}|{root}/backup-binary|{active_metadata}|{root}/backup-metadata\n')
   runtime_candidate=root/'runtime-new'; runtime_candidate.write_text('new-runtime'); runtime_target=root/'runtime'; runtime_target.write_text('old-runtime')
   units=root/'units'; units.mkdir(); unit_candidate=root/'unit-new'; unit_candidate.write_text('new-unit'); (units/'snell.service').write_text('old-unit')
   service_desc=root/'services'; service_desc.write_text(f'snell|{runtime_candidate}|{runtime_target}|{root}/backup-runtime|{units}|snell.service|{unit_candidate}|{root}/backup-unit\n')
   entry=root/'entry'; entry.write_text('Node = snell, node.example.com, 443, psk=test, version=6\n'); entries=root/'entries'; entries.write_text(str(entry)+'\n')
   body=f'''source "{COORD}"
ok() {{ return 0; }}
bad() {{ return 1; }}
deploy_coordinator_execute "{root}/binary-lock" "{root}/service-lock" deploy "{binary_desc}" "{service_desc}" "{root}/export" "{entries}" ok ok ok ok ok bad ok ok
code=$?; exit "$code"
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,env=dict(os.environ,SYSTEMCTL_BIN=str(mock)),check=False)
   self.assertNotEqual(result.returncode,0); self.assertEqual(active.read_text(),'old-binary'); self.assertEqual(active_metadata.read_text(),'old-metadata'); self.assertEqual(runtime_target.read_text(),'old-runtime')

 def test_incomplete_firewall_inputs_are_rejected_before_binary_change(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); work=root/'binary-work'; work.mkdir()
   candidate=work/'candidate'; candidate.write_text('#!/usr/bin/env bash\necho v5.0.1\n'); candidate.chmod(0o700)
   (work/'metadata').write_text('binary_id=snell-server\nversion=v5.0.1\nstability=beta\nrelease_date=2026-06-12\nplatform=linux-amd64\nsource=https://example.test/snell\nsha256='+'a'*64+'\n')
   active=root/'snell'; active.write_text('old-binary'); active.chmod(0o700)
   metadata=root/'snell.metadata'; metadata.write_text('old-metadata')
   binary_desc=root/'binaries'; binary_desc.write_text(f'snell|{work}|{active}|{root}/backup-binary|{metadata}|{root}/backup-metadata\n')
   entries=root/'entries'; entry=root/'entry'; entry.write_text('entry'); entries.write_text(str(entry)+'\n')
   body=f'''source "{COORD}"
ok() {{ return 0; }}
DEPLOY_FIREWALL_DESCRIPTOR="{root}/missing.descriptor"
deploy_coordinator_execute "{root}/binary-lock" "{root}/service-lock" deploy "{binary_desc}" "{root}/missing-services" "{root}/export" "{entries}" ok ok ok ok ok ok ok ok
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,check=False)
   self.assertNotEqual(result.returncode,0)
   self.assertEqual(active.read_text(),'old-binary'); self.assertEqual(metadata.read_text(),'old-metadata')
   self.assertFalse((root/'backup-binary.state').exists())

 def test_invalid_certificate_inputs_are_rejected_before_binary_change(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); work=root/'binary-work'; work.mkdir()
   candidate=work/'candidate'; candidate.write_text('#!/usr/bin/env bash\necho v5.0.1\n'); candidate.chmod(0o700)
   (work/'metadata').write_text('binary_id=snell-server\nversion=v5.0.1\nstability=beta\nrelease_date=2026-06-12\nplatform=linux-amd64\nsource=https://example.test/snell\nsha256='+'a'*64+'\n')
   active=root/'snell'; active.write_text('old-binary'); active.chmod(0o700)
   metadata=root/'snell.metadata'; metadata.write_text('old-metadata')
   binary_desc=root/'binaries'; binary_desc.write_text(f'snell|{work}|{active}|{root}/backup-binary|{metadata}|{root}/backup-metadata\n')
   runtime_candidate=root/'runtime-new'; runtime_candidate.write_text('new-runtime'); unit_candidate=root/'unit-new'; unit_candidate.write_text('new-unit')
   service_desc=root/'services'; service_desc.write_text(f'snell|{runtime_candidate}|{root}/runtime|{root}/backup-runtime|{root}/units|snell.service|{unit_candidate}|{root}/backup-unit\n')
   entries=root/'entries'; entry=root/'entry'; entry.write_text('entry'); entries.write_text(str(entry)+'\n')
   body=f'''source "{COORD}"
ok() {{ return 0; }}
DEPLOY_CERTIFICATE_CANDIDATE_CERT="{root}/missing-cert"
deploy_coordinator_execute "{root}/binary-lock" "{root}/service-lock" deploy "{binary_desc}" "{service_desc}" "{root}/export" "{entries}" ok ok ok ok ok ok ok ok
'''
   result=subprocess.run(['bash','-c',body],text=True,capture_output=True,check=False)
   self.assertEqual(result.returncode,2)
   self.assertEqual(active.read_text(),'old-binary'); self.assertEqual(metadata.read_text(),'old-metadata')
   self.assertFalse((root/'backup-binary.state').exists())

if __name__=='__main__': unittest.main()
