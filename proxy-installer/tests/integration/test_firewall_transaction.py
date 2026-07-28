import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIREWALL = ROOT / "lib" / "resources" / "firewall.sh"
TRANSACTION = ROOT / "lib" / "transaction" / "transaction.sh"


class FirewallTransactionTests(unittest.TestCase):
    def test_applied_auto_rule_makes_later_rollback_dirty_without_deletion(self):
        with tempfile.TemporaryDirectory() as temp_text:
            temp = Path(temp_text)
            calls = temp / "calls"
            context = temp / "firewall.context"
            lock = temp / "lock"
            ufw = temp / "ufw"
            ufw.write_text(
                '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\n',
                encoding="utf-8",
            )
            ufw.chmod(0o700)
            body = f'''
source "{TRANSACTION}"
source "{FIREWALL}"
apply_firewall() {{ firewall_apply_with_context "{context}" auto ufw false tcp:443; }}
rollback_firewall() {{ firewall_rollback_from_context "{context}"; }}
snapshot() {{ return 0; }}
health() {{ return 1; }}
commit() {{ return 0; }}
export_client() {{ return 0; }}
history() {{ return 0; }}
transaction_reset firewall-op "{lock}"
transaction_add_step firewall apply_firewall rollback_firewall
transaction_run snapshot health commit export_client history
code=$?
printf 'RESULT=%s\\nSTAGE=%s\\nADVICE=%s\\n' "$TX_RESULT" "$TX_FAILED_STAGE" "$TX_REPAIR_ADVICE"
exit "$code"
'''
            result = subprocess.run(
                ["bash", "-c", body],
                text=True,
                capture_output=True,
                env=dict(os.environ, UFW_BIN=str(ufw), MOCK_CALLS=str(calls)),
                check=False,
            )
            recorded = calls.read_text(encoding="utf-8").splitlines()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RESULT=dirty", result.stdout)
        self.assertIn("STAGE=health-verification", result.stdout)
        self.assertIn("inspect operation firewall-op snapshots", result.stdout)
        self.assertIn("manual-firewall-review=tcp:443", result.stderr)
        self.assertEqual(recorded, ["allow 443/tcp"])


if __name__ == "__main__":
    unittest.main()
