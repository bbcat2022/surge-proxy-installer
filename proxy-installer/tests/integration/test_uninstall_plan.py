import subprocess
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PLANNER=ROOT/'lib'/'orchestrators'/'uninstall.sh'
class UninstallPlanTests(unittest.TestCase):
 def run_plan(self,e): return subprocess.run(['bash','-c',f'source "{PLANNER}"; {e}'],text=True,capture_output=True,check=False)
 def test_snell_uninstall_does_not_touch_certificate(self):
  r=self.run_plan('uninstall_plan snell,anytls snell')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=unchanged',r.stdout); self.assertIn('firewall-cleanup=false',r.stdout)
 def test_last_tls_protocol_keeps_certificate_for_manual_cleanup(self):
  r=self.run_plan('uninstall_plan hysteria2 hysteria2')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=retain-manual-cleanup',r.stdout); self.assertIn('certificate-timer=retain',r.stdout)
 def test_shared_tls_certificate_is_protected(self):
  r=self.run_plan('uninstall_plan anytls,hysteria2 anytls')
  self.assertEqual(r.returncode,0); self.assertIn('certificate=shared-in-use',r.stdout)
 def test_not_installed_protocol_rejected(self): self.assertNotEqual(self.run_plan('uninstall_plan snell hysteria2').returncode,0)
if __name__=='__main__': unittest.main()
