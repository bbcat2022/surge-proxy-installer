import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BOOTSTRAP=ROOT/'bootstrap'/'install.sh'
BUILD=ROOT/'packaging'/'build.sh'

class GitHubBootstrapSmokeTests(unittest.TestCase):
 def test_verified_release_installs_manager_and_initializes_config(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t)
   built=subprocess.run(['bash',str(BUILD),str(root)],text=True,capture_output=True,check=False)
   archive=Path(built.stdout.strip())
   checksum=hashlib.sha256(archive.read_bytes()).hexdigest()
   curl=root/'curl'
   curl.write_text('#!/usr/bin/env bash\ncp "$SOURCE_ARCHIVE" "$6"\n',encoding='utf-8'); curl.chmod(0o700)
   install_root=root/'opt'/'proxy-installer'; config_root=root/'etc'/'proxy-installer'; binary=root/'bin'/'proxy-installer'
   env=dict(os.environ,INSTALL_EUID='0',CURL_BIN=str(curl),SOURCE_ARCHIVE=str(archive),INSTALL_ROOT=str(install_root),CONFIG_ROOT=str(config_root),BIN_PATH=str(binary),PYTHONPATH=str(ROOT.parent/'.python-packages'))
   result=subprocess.run(['bash',str(BOOTSTRAP),'--release-url','https://example.test/release.tar.gz','--sha256',checksum,'--version','v0.1.0','--skip-dependencies'],text=True,capture_output=True,env=env,check=False)
   config=subprocess.run(['python3',str(install_root/'tools'/'config_tool.py'),'--config',str(config_root/'config.yaml'),'validate'],text=True,capture_output=True,env=env,check=False)
   manifest=(install_root/'INSTALL-MANIFEST').read_text(encoding='utf-8')
   binary_exists=binary.exists()
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('success=manager-installed',result.stdout)
  self.assertEqual(config.returncode,0,config.stderr)
  self.assertTrue(binary_exists)
  self.assertIn('version=v0.1.0',manifest)
 def test_checksum_failure_leaves_install_root_absent(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); curl=root/'curl'; curl.write_text('#!/usr/bin/env bash\nprintf bogus > "$6"\n',encoding='utf-8'); curl.chmod(0o700)
   install_root=root/'opt'/'proxy-installer'
   env=dict(os.environ,INSTALL_EUID='0',CURL_BIN=str(curl),INSTALL_ROOT=str(install_root),CONFIG_ROOT=str(root/'etc'),BIN_PATH=str(root/'bin'/'proxy-installer'))
   result=subprocess.run(['bash',str(BOOTSTRAP),'--release-url','https://example.test/release.tar.gz','--sha256','0'*64,'--skip-dependencies'],text=True,capture_output=True,env=env,check=False)
  self.assertNotEqual(result.returncode,0)
  self.assertFalse(install_root.exists())

if __name__=='__main__': unittest.main()
