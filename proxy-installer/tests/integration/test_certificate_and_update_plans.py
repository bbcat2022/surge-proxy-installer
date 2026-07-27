import subprocess
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CERT=ROOT/'lib'/'orchestrators'/'certificate_workflow.sh'
UPDATE=ROOT/'lib'/'orchestrators'/'update.sh'
class CertificateAndUpdatePlanTests(unittest.TestCase):
 def run_plan(self,script,e): return subprocess.run(['bash','-c',f'source "{script}"; {e}'],text=True,capture_output=True,check=False)
 def test_certificate_issue_protects_port80_owner_and_old_certificate(self):
  r=self.run_plan(CERT,'certificate_workflow_plan issue node.example.com nginx anytls,hysteria2')
  self.assertEqual(r.returncode,0); self.assertIn('backup-active-certificate=true',r.stdout); self.assertIn('stop-owner-after-confirmation=true',r.stdout); self.assertIn('restore-owner=true',r.stdout)
 def test_cleanup_refuses_when_tls_service_still_depends_on_certificate(self): self.assertNotEqual(self.run_plan(CERT,'certificate_workflow_plan cleanup node.example.com none hysteria2').returncode,0)
 def test_update_requires_candidate_validation_and_sequential_batch_stop(self):
  r=self.run_plan(UPDATE,'update_plan snell v1.0.0 v1.0.1 true')
  self.assertEqual(r.returncode,0); self.assertIn('checksum-required=true',r.stdout); self.assertIn('batch=sequential-stop-on-failure',r.stdout)
 def test_invalid_update_version_is_rejected(self): self.assertNotEqual(self.run_plan(UPDATE,'update_plan snell latest v1.0.1 false').returncode,0)
if __name__=='__main__': unittest.main()
