import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
GATE=ROOT/'bin'/'preacceptance.sh'

class PreacceptanceSmokeTests(unittest.TestCase):
 def test_static_gate_generates_explicit_non_real_report(self):
  with tempfile.TemporaryDirectory() as t:
   report=Path(t)/'report.txt'
   result=subprocess.run(['bash',str(GATE),'--report',str(report)],text=True,capture_output=True,env=dict(os.environ))
   content=report.read_text()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('local_preacceptance=pass',content)
  self.assertIn('real_acceptance=not-run',content)

if __name__=='__main__': unittest.main()
