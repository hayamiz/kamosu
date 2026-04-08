#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CLI="${SCRIPT_DIR}/../cli/kamosu"
WORK_DIR="/tmp/kamosu-promote-test-$$"

setup
mkdir -p "${WORK_DIR}"

# Create mock docker and git
MOCK_BIN="${WORK_DIR}/mock-bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "${KAMOSU_MOCK_LOG}"
if [[ "${1:-}" == "info" ]]; then exit 0; fi
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "version" ]]; then echo "v2.40.0"; exit 0; fi
if [[ "${1:-}" == "inspect" ]]; then echo "0.2.0"; exit 0; fi
if [[ "${1:-}" == "run" ]] && [[ "$*" == *"--entrypoint cat"* ]]; then echo "mock prompt {{FILE_LIST}} {{TODAY}}"; exit 0; fi
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "run" ]]; then exit 0; fi
exit 0
MOCK
chmod +x "${MOCK_BIN}/docker"

cat > "${MOCK_BIN}/git" <<'MOCK'
#!/usr/bin/env bash
echo "git $*" >> "${KAMOSU_MOCK_LOG}"
if [[ "${1:-}" == "rev-parse" ]]; then exit 0; fi
if [[ "${1:-}" == "remote" ]]; then echo "origin	https://github.com/test/repo.git (fetch)"; exit 0; fi
if [[ "${1:-}" == "branch" ]] && [[ "${2:-}" == "--show-current" ]]; then echo "main"; exit 0; fi
exit 0
MOCK
chmod +x "${MOCK_BIN}/git"

export KAMOSU_MOCK_LOG="${WORK_DIR}/mock-calls.log"

run_cli() {
  > "${KAMOSU_MOCK_LOG}"
  PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@"
}

run_cli_capture() {
  > "${KAMOSU_MOCK_LOG}"
  PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@" 2>&1
}

run_cli_expect_fail() {
  > "${KAMOSU_MOCK_LOG}"
  if PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@" 2>/dev/null; then
    return 1
  else
    return 0
  fi
}

# Setup a fake data repo
setup_repo() {
  rm -rf "${WORK_DIR}/repo"
  mkdir -p "${WORK_DIR}/repo/raw" "${WORK_DIR}/repo/wiki" "${WORK_DIR}/repo/outputs"
  echo "0.2.0" > "${WORK_DIR}/repo/.kamosu-version"
  echo "CLAUDE.md" > "${WORK_DIR}/repo/CLAUDE.md"
}

# ============================================================
echo "--- Test: --help shows usage ---"
# ============================================================
output="$(run_cli_capture promote --help)"
assert_file_contains <(echo "$output") "Usage: kamosu promote" "promote --help shows usage"

# ============================================================
echo "--- Test: error outside data repo ---"
# ============================================================
cd "${WORK_DIR}"
rm -f "${WORK_DIR}/.kamosu-version"
run_cli_expect_fail promote --list
assert_eq 0 $? "promote fails outside data repo"

# ============================================================
echo "--- Test: error on non-existent file ---"
# ============================================================
setup_repo
cd "${WORK_DIR}/repo"
run_cli_expect_fail promote outputs/nonexistent.md
assert_eq 0 $? "promote fails on nonexistent file"

# ============================================================
echo "--- Test: error with no files specified ---"
# ============================================================
cd "${WORK_DIR}/repo"
run_cli_expect_fail promote
assert_eq 0 $? "promote fails with no files"

# ============================================================
echo "--- Test: --list with no outputs ---"
# ============================================================
setup_repo
rm -rf "${WORK_DIR}/repo/outputs"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture promote --list)"
assert_file_contains <(echo "$output") "No outputs/ directory" "--list handles missing outputs/"

# ============================================================
echo "--- Test: --list shows unpromoted files ---"
# ============================================================
setup_repo
echo "analysis content" > "${WORK_DIR}/repo/outputs/analysis.md"
echo "comparison content" > "${WORK_DIR}/repo/outputs/comparison.md"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture promote --list)"
assert_file_contains <(echo "$output") "outputs/analysis.md" "--list shows analysis.md"
assert_file_contains <(echo "$output") "outputs/comparison.md" "--list shows comparison.md"

# ============================================================
echo "--- Test: --list filters promoted files ---"
# ============================================================
echo "2026-04-08T00:00:00Z	outputs/analysis.md" > "${WORK_DIR}/repo/.promote-history"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture promote --list)"
assert_file_not_contains <(echo "$output") "analysis.md" "--list filters promoted files"
assert_file_contains <(echo "$output") "comparison.md" "--list shows unpromoted files"

# ============================================================
echo "--- Test: --list does not call Docker ---"
# ============================================================
cd "${WORK_DIR}/repo"
run_cli promote --list >/dev/null 2>&1 || true
if grep -q "docker compose run" "${KAMOSU_MOCK_LOG}" 2>/dev/null; then
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: --list should not invoke Docker"
else
  ASSERTIONS=$((ASSERTIONS + 1))
fi

# ============================================================
echo "--- Test: --dry-run does not write .promote-history ---"
# ============================================================
setup_repo
echo "test content" > "${WORK_DIR}/repo/outputs/test-output.md"
cd "${WORK_DIR}/repo"
run_cli promote --dry-run outputs/test-output.md
ASSERTIONS=$((ASSERTIONS + 1))
if [[ ! -f "${WORK_DIR}/repo/.promote-history" ]]; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: --dry-run should not write .promote-history"
fi

# ============================================================
echo "--- Test: full promote records history ---"
# ============================================================
setup_repo
echo "test content" > "${WORK_DIR}/repo/outputs/full-test.md"
cd "${WORK_DIR}/repo"
run_cli promote outputs/full-test.md
assert_file_exists "${WORK_DIR}/repo/.promote-history" ".promote-history created"
assert_file_contains "${WORK_DIR}/repo/.promote-history" "outputs/full-test.md" ".promote-history records file"

# ============================================================
echo "--- Test: promote invokes Claude via Docker ---"
# ============================================================
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb bash" "promote invokes claude via docker (stream pipeline)"

# ============================================================
echo "--- Test: promote runs git commit on host ---"
# ============================================================
assert_file_contains "${KAMOSU_MOCK_LOG}" "git add" "promote runs git add"
assert_file_contains "${KAMOSU_MOCK_LOG}" "git commit" "promote runs git commit"

# ============================================================
# Cleanup
# ============================================================
rm -rf "${WORK_DIR}"
teardown

report
