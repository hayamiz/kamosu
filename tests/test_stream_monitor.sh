#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

MONITOR="${SCRIPT_DIR}/../tools/stream-monitor.py"
FIXTURES="${SCRIPT_DIR}/fixtures"
WORK_DIR="/tmp/kamosu-stream-test-$$"

setup
mkdir -p "${WORK_DIR}"

# ============================================================
echo "--- Test: success fixture exits 0 ---"
# ============================================================
result=$(cat "${FIXTURES}/stream-success.jsonl" \
  | python3 "${MONITOR}" --json-summary --log "${WORK_DIR}/test-success.jsonl" 2>/dev/null)
exit_code=$?
assert_eq 0 "${exit_code}" "success fixture should exit 0"

# ============================================================
echo "--- Test: success fixture JSON summary ---"
# ============================================================
status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
assert_eq "success" "${status}" "status should be success"

num_turns=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['num_turns'])")
assert_eq "2" "${num_turns}" "num_turns should be 2"

cost=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if d['cost_usd'] > 0 else 'no')")
assert_eq "yes" "${cost}" "cost should be > 0"

denials=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['permission_denials']))")
assert_eq "0" "${denials}" "should have no permission denials"

# ============================================================
echo "--- Test: success fixture creates log file ---"
# ============================================================
assert_file_exists "${WORK_DIR}/test-success.jsonl" "log file should be created"
# Log should contain same number of non-empty lines as fixture
fixture_lines=$(grep -c '.' "${FIXTURES}/stream-success.jsonl")
log_lines=$(grep -c '.' "${WORK_DIR}/test-success.jsonl")
assert_eq "${fixture_lines}" "${log_lines}" "log should contain all events"

# ============================================================
echo "--- Test: error fixture exits 1 ---"
# ============================================================
result=$(cat "${FIXTURES}/stream-error.jsonl" \
  | python3 "${MONITOR}" --json-summary --log "${WORK_DIR}/test-error.jsonl" 2>/dev/null)
exit_code=$?
assert_eq 1 "${exit_code}" "error fixture should exit 1"

# ============================================================
echo "--- Test: error fixture JSON summary ---"
# ============================================================
status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
assert_eq "error" "${status}" "status should be error"

stop_reason=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['stop_reason'])")
assert_eq "budget_exceeded" "${stop_reason}" "stop_reason should be budget_exceeded"

# ============================================================
echo "--- Test: permission denied fixture exits 1 ---"
# ============================================================
result=$(cat "${FIXTURES}/stream-permission-denied.jsonl" \
  | python3 "${MONITOR}" --json-summary --log "${WORK_DIR}/test-perm.jsonl" 2>/dev/null)
exit_code=$?
assert_eq 1 "${exit_code}" "permission denied fixture should exit 1"

# ============================================================
echo "--- Test: permission denied reports denials ---"
# ============================================================
denials=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['permission_denials']))")
assert_eq "1" "${denials}" "should have 1 permission denial"

denial_text=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['permission_denials'][0])")
ASSERTIONS=$((ASSERTIONS + 1))
if echo "${denial_text}" | grep -q "Bash"; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: denial should mention Bash tool (got: ${denial_text})"
fi

# ============================================================
echo "--- Test: human-readable output on success ---"
# ============================================================
output=$(cat "${FIXTURES}/stream-success.jsonl" \
  | python3 "${MONITOR}" --log "${WORK_DIR}/test-human.jsonl" 2>/dev/null)
ASSERTIONS=$((ASSERTIONS + 1))
if echo "${output}" | grep -q "complete"; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: human output should contain 'complete' (got: ${output})"
fi

# ============================================================
echo "--- Test: human-readable output on failure shows log path ---"
# ============================================================
output=$(cat "${FIXTURES}/stream-error.jsonl" \
  | python3 "${MONITOR}" --log "${WORK_DIR}/test-human-err.jsonl" 2>/dev/null)
ASSERTIONS=$((ASSERTIONS + 1))
if echo "${output}" | grep -q "Details:"; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: failure output should show log path (got: ${output})"
fi

# ============================================================
echo "--- Test: malformed JSON lines are skipped ---"
# ============================================================
# Create a fixture with a bad line
{
  echo "not valid json"
  cat "${FIXTURES}/stream-success.jsonl"
} | python3 "${MONITOR}" --json-summary --log "${WORK_DIR}/test-malformed.jsonl" 2>/dev/null > "${WORK_DIR}/malformed-result.json"
malformed=$(python3 -c "import json; print(json.load(open('${WORK_DIR}/malformed-result.json'))['malformed_lines'])")
assert_eq "1" "${malformed}" "should report 1 malformed line"

# ============================================================
echo "--- Test: empty input exits 1 ---"
# ============================================================
echo "" | python3 "${MONITOR}" --json-summary --log "${WORK_DIR}/test-empty.jsonl" 2>/dev/null
exit_code=$?
assert_eq 1 "${exit_code}" "empty input should exit 1 (no result event)"

# ============================================================
# Cleanup
# ============================================================
rm -rf "${WORK_DIR}"
teardown

report
