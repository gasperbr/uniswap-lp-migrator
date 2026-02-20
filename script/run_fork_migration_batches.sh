#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${ETH_RPC_URL:-https://eth.llamarpc.com}"
TEST_TARGET="${TEST_TARGET:-all}" # all | v3 | v4
TOTAL_POSITIONS="${TOTAL_POSITIONS:-100}"
BATCH_SIZE="${BATCH_SIZE:-10}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
SLEEP_BETWEEN_BATCHES="${SLEEP_BETWEEN_BATCHES:-1}"
FOUNDRY_TEST_DIR="${FOUNDRY_TEST:-test}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-1}"

V3_PATH="test/UniV3ToEkuboMigrator.fork.t.sol"
V4_PATH="test/UniV4ToEkuboMigrator.fork.t.sol"
V3_TEST_NAME="testForkMigrateLatestV3LiquidPositionsBatch"
V4_TEST_NAME="testForkMigrateLatestV4LiquidPositionsBatch"

if (( BATCH_SIZE <= 0 )); then
  echo "BATCH_SIZE must be > 0"
  exit 1
fi

if (( TOTAL_POSITIONS <= 0 )); then
  echo "TOTAL_POSITIONS must be > 0"
  exit 1
fi

if (( TOTAL_POSITIONS % BATCH_SIZE != 0 )); then
  echo "TOTAL_POSITIONS must be divisible by BATCH_SIZE"
  exit 1
fi

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return $?
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
    return $?
  fi

  "$@" &
  local pid="$!"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= seconds )); then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

if [[ -z "${FORK_BLOCK_NUMBER:-}" ]]; then
  FORK_BLOCK_NUMBER="$(cast block-number --rpc-url "$RPC_URL")"
fi

run_batch() {
  local label="$1"
  local match_path="$2"
  local match_test="$3"
  local offset="$4"

  echo
  echo "==> ${label} batch offset=${offset} count=${BATCH_SIZE} block=${FORK_BLOCK_NUMBER}"
  run_with_timeout "$TIMEOUT_SECONDS" \
    env \
      ETH_RPC_URL="$RPC_URL" \
      FORK_BLOCK_NUMBER="$FORK_BLOCK_NUMBER" \
      FOUNDRY_TEST="$FOUNDRY_TEST_DIR" \
      POSITION_OFFSET="$offset" \
      POSITION_COUNT="$BATCH_SIZE" \
      forge test --match-path "$match_path" --match-test "$match_test" -vv
}

run_target_batches() {
  local label="$1"
  local match_path="$2"
  local match_test="$3"
  local offset=0
  local failed=0

  while (( offset < TOTAL_POSITIONS )); do
    if ! run_batch "$label" "$match_path" "$match_test" "$offset"; then
      echo "Batch failed: ${label} offset=${offset} count=${BATCH_SIZE}"
      failed=1
      if [[ "$CONTINUE_ON_FAILURE" != "1" ]]; then
        return 1
      fi
    fi
    offset=$((offset + BATCH_SIZE))
    sleep "$SLEEP_BETWEEN_BATCHES"
  done

  return "$failed"
}

echo "Using RPC: ${RPC_URL}"
echo "Pinned fork block: ${FORK_BLOCK_NUMBER}"
echo "Target: ${TEST_TARGET}, total positions: ${TOTAL_POSITIONS}, batch size: ${BATCH_SIZE}"
echo "Continue on failure: ${CONTINUE_ON_FAILURE}"

overall_failed=0
case "$TEST_TARGET" in
  all)
    run_target_batches "UniV3" "$V3_PATH" "$V3_TEST_NAME" || overall_failed=1
    run_target_batches "UniV4" "$V4_PATH" "$V4_TEST_NAME" || overall_failed=1
    ;;
  v3)
    run_target_batches "UniV3" "$V3_PATH" "$V3_TEST_NAME" || overall_failed=1
    ;;
  v4)
    run_target_batches "UniV4" "$V4_PATH" "$V4_TEST_NAME" || overall_failed=1
    ;;
  *)
    echo "Unsupported TEST_TARGET: ${TEST_TARGET} (use all|v3|v4)"
    exit 1
    ;;
esac

echo
if (( overall_failed == 0 )); then
  echo "All requested batches completed."
else
  echo "Batch execution completed with failures."
  exit 1
fi
