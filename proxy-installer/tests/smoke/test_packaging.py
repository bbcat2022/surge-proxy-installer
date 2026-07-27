import subprocess,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'packaging'/'build.sh'; SMOKE=ROOT/'packaging'/'smoke.sh'
class PackagingSmokeTests(unittest.TestCase):
 def test_package_build_and_unpack_smoke(self):
  with tempfile.TemporaryDirectory() as t:
   built=subprocess.run(['bash',str(BUILD),t],text=True,capture_output=True,check=False)
   package=Path(built.stdout.strip())
   smoke=subprocess.run(['bash',str(SMOKE),str(package)],text=True,capture_output=True,check=False)
  self.assertEqual(built.returncode,0,built.stderr); self.assertEqual(smoke.returncode,0,smoke.stderr); self.assertIn('package-smoke=success',smoke.stdout)
if __name__=='__main__': unittest.main()
