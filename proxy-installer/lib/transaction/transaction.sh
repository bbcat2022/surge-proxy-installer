#!/usr/bin/env bash
# Reusable high-impact operation transaction skeleton.

set -o pipefail

TX_OPERATION_ID=""
TX_LOCK_DIR=""
TX_RESULT=""
TX_SUMMARY=""
TX_ACTIVE_OPERATION_ID=""
TX_PENDING_CALLBACK=""
TX_RESTORE_VERIFY_CALLBACK=""
TX_RESULT_CALLBACK=""
TX_FAILED_STAGE=""
TX_REPAIR_ADVICE=""
TX_EXECUTED=()
TX_STEP_NAMES=()
TX_STEP_APPLY=()
TX_STEP_ROLLBACK=()

transaction_reset() {
  TX_OPERATION_ID="$1"
  TX_LOCK_DIR="${TRANSACTION_GLOBAL_LOCK_DIR:-$2}"
  TX_RESULT=""
  TX_SUMMARY=""
  TX_ACTIVE_OPERATION_ID=""
  TX_PENDING_CALLBACK=""
  TX_RESTORE_VERIFY_CALLBACK=""
  TX_RESULT_CALLBACK=""
  TX_FAILED_STAGE=""
  TX_REPAIR_ADVICE=""
  TX_EXECUTED=()
  TX_STEP_NAMES=()
  TX_STEP_APPLY=()
  TX_STEP_ROLLBACK=()
}

transaction_function_exists() {
  declare -F "$1" >/dev/null
}

transaction_set_dirty_advice() {
  TX_REPAIR_ADVICE="inspect operation ${TX_OPERATION_ID} snapshots and restore failed resources before retrying"
}

transaction_set_pending_callback() {
  [ "$#" -eq 1 ] && transaction_function_exists "$1" || return 1
  TX_PENDING_CALLBACK="$1"
}

transaction_set_restore_verify_callback() {
  [ "$#" -eq 1 ] && transaction_function_exists "$1" || return 1
  TX_RESTORE_VERIFY_CALLBACK="$1"
}

transaction_set_result_callback() {
  [ "$#" -eq 1 ] && transaction_function_exists "$1" || return 1
  TX_RESULT_CALLBACK="$1"
}

transaction_notify_result() {
  [ -n "${TX_RESULT_CALLBACK}" ] || return 0
  if ! "${TX_RESULT_CALLBACK}" "${TX_OPERATION_ID}" "${TX_RESULT}" "${TX_FAILED_STAGE}" "${TX_SUMMARY}" "${TX_REPAIR_ADVICE}"; then
    if [ "${TX_RESULT}" = "success" ]; then
      TX_RESULT="partial-success"
      TX_FAILED_STAGE="result-record"
      TX_SUMMARY="operation succeeded but final result recording failed"
    else
      TX_SUMMARY="${TX_SUMMARY}; final result recording failed"
    fi
    return 1
  fi
}

transaction_add_step() {
  local name="$1"
  local apply_function="$2"
  local rollback_function="$3"
  local existing
  if ! [[ "${name}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] ||
     ! transaction_function_exists "${apply_function}" ||
     ! transaction_function_exists "${rollback_function}"; then
    return 1
  fi
  for existing in "${TX_STEP_NAMES[@]}"; do [ "${existing}" != "${name}" ] || return 1; done
  TX_STEP_NAMES+=("${name}")
  TX_STEP_APPLY+=("${apply_function}")
  TX_STEP_ROLLBACK+=("${rollback_function}")
}

transaction_acquire_lock() {
  if ! mkdir "${TX_LOCK_DIR}" 2>/dev/null; then
    TX_RESULT="failed"
    TX_FAILED_STAGE="operation-lock"
    if [ -f "${TX_LOCK_DIR}/operation-id" ]; then
      IFS= read -r TX_ACTIVE_OPERATION_ID < "${TX_LOCK_DIR}/operation-id" || TX_ACTIVE_OPERATION_ID=""
    fi
    if [[ "${TX_ACTIVE_OPERATION_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
      TX_SUMMARY="operation lock is already held by ${TX_ACTIVE_OPERATION_ID}"
    else
      TX_ACTIVE_OPERATION_ID=""
      TX_SUMMARY="operation lock is already held"
    fi
    return 1
  fi
  if ! chmod 700 "${TX_LOCK_DIR}" ||
     ! printf '%s\n' "${TX_OPERATION_ID}" > "${TX_LOCK_DIR}/operation-id" ||
     ! chmod 600 "${TX_LOCK_DIR}/operation-id"; then
    rm -f "${TX_LOCK_DIR}/operation-id"
    rmdir "${TX_LOCK_DIR}" 2>/dev/null || true
    TX_RESULT="failed"
    TX_FAILED_STAGE="operation-lock"
    TX_SUMMARY="operation lock could not be initialized"
    return 1
  fi
}

transaction_release_lock() {
  [ -d "${TX_LOCK_DIR}" ] || return 0
  rm -f "${TX_LOCK_DIR}/operation-id" || return 1
  rmdir "${TX_LOCK_DIR}" || return 1
}

transaction_clear_interrupt_trap() {
  trap - INT TERM
}

transaction_finalize_locked_result() {
  local lock_failure_summary="$1"
  # Record the terminal state while the global operation lock is still held so
  # a following operation cannot overwrite it before this operation publishes.
  transaction_notify_result || true
  if ! transaction_release_lock; then
    TX_RESULT="dirty"
    TX_SUMMARY="${lock_failure_summary}"
    transaction_set_dirty_advice
    transaction_notify_result || true
  fi
  transaction_clear_interrupt_trap
}

transaction_interrupt() {
  TX_FAILED_STAGE="interrupted"
  transaction_rollback
  [ "${TX_RESULT}" = "dirty" ] || {
    TX_RESULT="rollback-success"
    TX_SUMMARY="operation interrupted and completed steps were restored"
  }
  transaction_finalize_locked_result "operation interrupted and lock cleanup is incomplete"
}

transaction_validate_plan() {
  local index
  [[ "${TX_OPERATION_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
  [[ "${TX_LOCK_DIR}" = /* ]] && [ -n "${TX_LOCK_DIR}" ] || return 1
  [ "${#TX_STEP_NAMES[@]}" -gt 0 ] || return 1
  for index in "${!TX_STEP_NAMES[@]}"; do
    transaction_function_exists "${TX_STEP_APPLY[${index}]}" || return 1
    transaction_function_exists "${TX_STEP_ROLLBACK[${index}]}" || return 1
  done
}

transaction_rollback() {
  local index rollback_failed=0
  for ((index=${#TX_EXECUTED[@]} - 1; index >= 0; index--)); do
    if ! "${TX_STEP_ROLLBACK[${TX_EXECUTED[${index}]}]}"; then
      rollback_failed=1
    fi
  done
  if [ "${rollback_failed}" -eq 0 ] && [ -n "${TX_RESTORE_VERIFY_CALLBACK}" ] && ! "${TX_RESTORE_VERIFY_CALLBACK}"; then
    TX_RESULT="dirty"
    TX_SUMMARY="operation rollback ran but restored state verification failed"
    transaction_set_dirty_advice
    return 1
  fi
  if [ "${rollback_failed}" -eq 1 ]; then
    TX_RESULT="dirty"
    TX_SUMMARY="operation failed and rollback is incomplete"
    transaction_set_dirty_advice
  else
    TX_RESULT="rollback-success"
    TX_SUMMARY="operation failed and completed steps were restored"
  fi
}

transaction_fail() {
  transaction_rollback
  transaction_finalize_locked_result "operation failed and lock cleanup is incomplete"
  return 1
}

transaction_run() {
  local snapshot_function="$1"
  local health_function="$2"
  local commit_function="$3"
  local export_function="$4"
  local history_function="$5"
  local index

  if ! transaction_validate_plan; then
    TX_RESULT="failed"
    TX_FAILED_STAGE="plan-validation"
    TX_SUMMARY="operation plan is incomplete"
    transaction_notify_result || true
    return 1
  fi
  if ! transaction_function_exists "${snapshot_function}" || ! transaction_function_exists "${health_function}" || ! transaction_function_exists "${commit_function}" || ! transaction_function_exists "${export_function}" || ! transaction_function_exists "${history_function}"; then
    TX_RESULT="failed"
    TX_FAILED_STAGE="dependency-validation"
    TX_SUMMARY="operation plan references an unavailable callback"
    transaction_notify_result || true
    return 1
  fi
  if ! transaction_acquire_lock; then transaction_notify_result || true; return 1; fi
  trap 'transaction_interrupt; exit 130' INT TERM
  if ! "${snapshot_function}"; then
    TX_RESULT="failed"
    TX_FAILED_STAGE="snapshot"
    TX_SUMMARY="transaction snapshot failed"
    transaction_finalize_locked_result "operation failed and lock cleanup is incomplete"
    return 1
  fi
  if [ -n "${TX_PENDING_CALLBACK}" ] && ! "${TX_PENDING_CALLBACK}"; then
    TX_RESULT="failed"
    TX_FAILED_STAGE="pending-state"
    TX_SUMMARY="operation pending state could not be recorded"
    transaction_finalize_locked_result "operation failed and lock cleanup is incomplete"
    return 1
  fi
  for index in "${!TX_STEP_NAMES[@]}"; do
    TX_EXECUTED+=("${index}")
    if ! "${TX_STEP_APPLY[${index}]}"; then
      TX_FAILED_STAGE="${TX_STEP_NAMES[${index}]}"
      transaction_fail
      return 1
    fi
  done
  if ! "${health_function}"; then
    TX_FAILED_STAGE="health-verification"
    transaction_fail
    return 1
  fi
  if ! "${commit_function}"; then
    TX_FAILED_STAGE="state-commit"
    transaction_fail
    return 1
  fi
  if ! "${export_function}"; then
    TX_RESULT="partial-success"
    TX_FAILED_STAGE="client-export"
    TX_SUMMARY="server changes are healthy but client export failed"
    transaction_finalize_locked_result "operation completed but lock cleanup is incomplete"
    return 0
  fi
  if ! "${history_function}"; then
    TX_RESULT="partial-success"
    TX_FAILED_STAGE="history"
    TX_SUMMARY="operation succeeded but history recording failed"
    transaction_finalize_locked_result "operation completed but lock cleanup is incomplete"
    return 0
  fi
  TX_RESULT="success"
  TX_SUMMARY="operation completed and passed health verification"
  transaction_finalize_locked_result "operation completed but lock cleanup is incomplete"
}
