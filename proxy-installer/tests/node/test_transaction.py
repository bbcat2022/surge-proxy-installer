import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TRANSACTION_SCRIPT = ROOT / "lib" / "transaction" / "transaction.sh"


class TransactionTests(unittest.TestCase):
    def run_case(self, body: str):
        prelude = f'''source "{TRANSACTION_SCRIPT}"
log="$1/log"
ok() {{ echo "$1" >> "$log"; return 0; }}
fail() {{ echo "$1" >> "$log"; return 1; }}
snapshot() {{ ok snapshot; }}
health() {{ ok health; }}
commit() {{ ok commit; }}
export_ok() {{ ok export; }}
export_fail() {{ fail export; }}
history() {{ ok history; }}
pending() {{ ok pending; }}
pending_fail() {{ fail pending-fail; }}
restore_verify() {{ ok restore-verify; }}
restore_verify_fail() {{ fail restore-verify-fail; }}
result_record() {{ printf 'result=%s|%s|%s\\n' "$1" "$2" "$3" >> "$log"; }}
result_record_fail() {{ fail result-record-fail; }}
apply_one() {{ ok apply-one; }}
apply_two() {{ ok apply-two; }}
apply_fail() {{ fail apply-fail; }}
rollback_one() {{ ok rollback-one; }}
rollback_two() {{ ok rollback-two; }}
rollback_fail() {{ fail rollback-fail; }}
'''
        with tempfile.TemporaryDirectory() as temp:
            command = prelude + "\n" + body + '\nprintf "%s:%s" "$TX_RESULT" "$TX_SUMMARY"\n'
            completed = subprocess.run(["bash", "-c", command, "transaction-test", temp], text=True, capture_output=True, check=False)
            log = (Path(temp) / "log").read_text(encoding="utf-8").splitlines() if (Path(temp) / "log").exists() else []
        return completed, log

    def test_failed_step_rolls_back_in_reverse_order(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_add_step two apply_fail rollback_two; transaction_run snapshot health commit export_ok history || true')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(log, ["snapshot", "apply-one", "apply-fail", "rollback-two", "rollback-one"])
        self.assertTrue(result.stdout.startswith("rollback-success:"))

    def test_health_failure_does_not_commit(self):
        result, log = self.run_case('health() { fail health; }; transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true')
        self.assertEqual(log, ["snapshot", "apply-one", "health", "rollback-one"])
        self.assertNotIn("commit", log)
        self.assertTrue(result.stdout.startswith("rollback-success:"))

    def test_pending_state_is_recorded_after_snapshot_before_resource_changes(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_set_pending_callback pending; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(log, ["snapshot", "pending", "apply-one", "health", "commit", "export", "history"])
        self.assertTrue(result.stdout.startswith("success:"))

    def test_pending_state_failure_stops_before_resource_changes(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_set_pending_callback pending_fail; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true')
        self.assertEqual(log, ["snapshot", "pending-fail"])
        self.assertTrue(result.stdout.startswith("failed:operation pending state could not be recorded"))

    def test_terminal_result_callback_receives_success_and_failure_context(self):
        success, success_log = self.run_case('transaction_reset op "$1/lock"; transaction_set_result_callback result_record; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history')
        failed, failed_log = self.run_case('transaction_reset op "$1/lock"; transaction_set_result_callback result_record; transaction_add_step one apply_fail rollback_one; transaction_run snapshot health commit export_ok history || true')
        self.assertIn("result=op|success|", success_log)
        self.assertIn("result=op|rollback-success|one", failed_log)
        self.assertTrue(success.stdout.startswith("success:"))
        self.assertTrue(failed.stdout.startswith("rollback-success:"))

    def test_success_result_record_failure_becomes_partial_success(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_set_result_callback result_record_fail; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history')
        self.assertIn("result-record-fail", log)
        self.assertTrue(result.stdout.startswith("partial-success:operation succeeded but final result recording failed"))

    def test_export_failure_keeps_committed_server_result(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_fail history')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(log, ["snapshot", "apply-one", "health", "commit", "export"])
        self.assertTrue(result.stdout.startswith("partial-success:"))

    def test_lock_conflict_rejects_second_operation(self):
        result, log = self.run_case('transaction_reset existing "$1/lock"; transaction_acquire_lock; transaction_reset second "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true; transaction_release_lock')
        self.assertEqual(log, [])
        self.assertTrue(result.stdout.startswith("failed:operation lock is already held by existing"))

    def test_configured_global_lock_serializes_different_orchestrators(self):
        result, log = self.run_case('TRANSACTION_GLOBAL_LOCK_DIR="$1/global-lock"; transaction_reset deploy "$1/deploy-lock"; transaction_acquire_lock; transaction_reset certificate "$1/certificate-lock"; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true; transaction_release_lock')
        self.assertEqual(log, [])
        self.assertTrue(result.stdout.startswith("failed:operation lock is already held by deploy"))

    def test_unsafe_operation_id_and_relative_lock_are_rejected_before_changes(self):
        result, log = self.run_case('transaction_reset "../unsafe" relative-lock; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true')
        self.assertEqual(log, [])
        self.assertTrue(result.stdout.startswith("failed:operation plan is incomplete"))

    def test_duplicate_or_unsafe_step_names_are_rejected(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_add_step one apply_two rollback_two || duplicate_rejected=true; transaction_add_step "bad step" apply_two rollback_two || unsafe_rejected=true; printf "%s:%s\\n" "$duplicate_rejected" "$unsafe_rejected"')
        self.assertEqual(log, [])
        self.assertTrue(result.stdout.startswith("true:true"))

    def test_rollback_failure_marks_dirty(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_fail; transaction_add_step two apply_fail rollback_two; transaction_run snapshot health commit export_ok history || true; printf "CONTEXT=%s|%s\\n" "$TX_FAILED_STAGE" "$TX_REPAIR_ADVICE"')
        self.assertEqual(log, ["snapshot", "apply-one", "apply-fail", "rollback-two", "rollback-fail"])
        self.assertIn("CONTEXT=two|inspect operation op snapshots and restore failed resources before retrying", result.stdout)
        self.assertTrue(result.stdout.rstrip().endswith("dirty:operation failed and rollback is incomplete"))

    def test_successful_rollback_verifies_restored_state(self):
        result, log = self.run_case('health() { fail health; }; transaction_reset op "$1/lock"; transaction_set_restore_verify_callback restore_verify; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true')
        self.assertEqual(log, ["snapshot", "apply-one", "health", "rollback-one", "restore-verify"])
        self.assertTrue(result.stdout.startswith("rollback-success:"))

    def test_failed_restored_state_verification_marks_dirty(self):
        result, log = self.run_case('health() { fail health; }; transaction_reset op "$1/lock"; transaction_set_restore_verify_callback restore_verify_fail; transaction_add_step one apply_one rollback_one; transaction_run snapshot health commit export_ok history || true; printf "CONTEXT=%s|%s\\n" "$TX_FAILED_STAGE" "$TX_REPAIR_ADVICE"')
        self.assertEqual(log, ["snapshot", "apply-one", "health", "rollback-one", "restore-verify-fail"])
        self.assertIn("CONTEXT=health-verification|inspect operation op snapshots and restore failed resources before retrying", result.stdout)
        self.assertTrue(result.stdout.rstrip().endswith("dirty:operation rollback ran but restored state verification failed"))

    def test_interruption_rolls_back_completed_steps_and_releases_lock(self):
        result, log = self.run_case('transaction_reset op "$1/lock"; transaction_add_step one apply_one rollback_one; transaction_acquire_lock; apply_one; TX_EXECUTED+=(0); transaction_interrupt; [ ! -d "$1/lock" ]')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(log, ["apply-one", "rollback-one"])
        self.assertTrue(result.stdout.startswith("rollback-success:operation interrupted"))


if __name__ == "__main__":
    unittest.main()
