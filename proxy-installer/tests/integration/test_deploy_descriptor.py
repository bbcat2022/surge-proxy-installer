import subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DESCRIPTOR=ROOT/'lib'/'orchestrators'/'deploy_descriptor.sh'

class DeployDescriptorTests(unittest.TestCase):
 def test_includes_port_hop_only_when_its_candidates_exist(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); candidate=root/'candidate'; candidate.mkdir(); runtime=root/'runtime'; unit=root/'units'; backup=root/'backup'; descriptor=root/'descriptor'
   for name in ('snell.conf','proxy-installer-snell.service','hysteria2.yaml','proxy-installer-hysteria2.service','hysteria2-port-hop.nft','proxy-installer-hysteria2-port-hop.service','snell.surge','hysteria2.surge'):
    (candidate/name).write_text('candidate')
   command=f'source "{DESCRIPTOR}"; deploy_descriptor_build "{candidate}" "{runtime}" "{unit}" "{backup}" "{descriptor}"; deploy_descriptor_entries "{candidate}"'
   result=subprocess.run(['bash','-c',command],text=True,capture_output=True,check=False)
   content=descriptor.read_text()
  self.assertEqual(result.returncode,0,result.stderr); self.assertIn('hysteria2-port-hop|',content); self.assertIn('snell|',content); self.assertIn(str(candidate/'snell.surge'),result.stdout)

if __name__=='__main__': unittest.main()
