#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CLI="${SCRIPT_DIR}/../cli/kamosu"
WORK_DIR="/tmp/kamosu-compile-test-$$"

setup
mkdir -p "${WORK_DIR}"

# Create a mock docker and git
MOCK_BIN="${WORK_DIR}/mock-bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "${KAMOSU_MOCK_LOG}"
if [[ "${1:-}" == "info" ]]; then exit 0; fi
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "version" ]]; then echo "v2.40.0"; exit 0; fi
if [[ "${1:-}" == "inspect" ]]; then echo "0.2.0"; exit 0; fi
if [[ "${1:-}" == "run" ]] && [[ "$*" == *"--entrypoint cat"* ]]; then echo "mock prompt"; exit 0; fi
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
  mkdir -p "${WORK_DIR}/repo/raw/papers" "${WORK_DIR}/repo/wiki/my-drafts" "${WORK_DIR}/repo/wiki/concepts" "${WORK_DIR}/repo/wiki/_category"
  echo "0.2.0" > "${WORK_DIR}/repo/.kb-toolkit-version"
}

# ============================================================
echo "--- Test: --dry-run with no files ---"
# ============================================================
setup_repo
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "No new or updated files" "dry-run with empty raw/ reports no files"

# ============================================================
echo "--- Test: --dry-run detects new files ---"
# ============================================================
echo "test content" > "${WORK_DIR}/repo/raw/papers/test-paper.txt"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "raw/papers/test-paper.txt" "dry-run detects new file"
assert_file_contains <(echo "$output") "Dry run complete" "dry-run shows completion message"

# ============================================================
echo "--- Test: --file with nonexistent file ---"
# ============================================================
cd "${WORK_DIR}/repo"
run_cli_expect_fail compile --file raw/nonexistent.pdf
assert_eq 0 $? "--file with nonexistent file should fail"

# ============================================================
echo "--- Test: timestamp-based diff detection ---"
# ============================================================
cd "${WORK_DIR}/repo"
touch "${WORK_DIR}/repo/.last-compile-timestamp"
sleep 1

# Existing file is older than timestamp — should NOT be detected
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "No new or updated files" "files older than timestamp not detected"

# Add a newer file — should be detected
echo "newer content" > "${WORK_DIR}/repo/raw/papers/newer-paper.txt"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "raw/papers/newer-paper.txt" "file newer than timestamp detected"
assert_file_not_contains <(echo "$output") "test-paper.txt" "old file not detected"

# ============================================================
echo "--- Test: --force recompiles all files ---"
# ============================================================
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile --force --dry-run)"
assert_file_contains <(echo "$output") "test-paper.txt" "--force includes old files"
assert_file_contains <(echo "$output") "newer-paper.txt" "--force includes new files"

# ============================================================
echo "--- Test: .ingest-queue stale detection ---"
# ============================================================
setup_repo
echo "raw/papers/old-queue.txt" > "${WORK_DIR}/repo/.ingest-queue"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile 2>&1 || true)"
assert_file_contains <(echo "$output") "previous compilation was interrupted" "stale queue detected"

# ============================================================
echo "--- Test: --clean removes stale queue ---"
# ============================================================
echo "raw/papers/old-queue.txt" > "${WORK_DIR}/repo/.ingest-queue"
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile --clean --dry-run)"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ ! -f "${WORK_DIR}/repo/.ingest-queue" ]]; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: --clean should remove .ingest-queue"
fi

# ============================================================
echo "--- Test: --resume uses existing queue ---"
# ============================================================
setup_repo
echo "test content" > "${WORK_DIR}/repo/raw/papers/queued-file.txt"
echo "raw/papers/queued-file.txt" > "${WORK_DIR}/repo/.ingest-queue"
cd "${WORK_DIR}/repo"
run_cli compile --resume
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb claude" "--resume invokes claude"
# Queue should be cleaned up after successful compile
ASSERTIONS=$((ASSERTIONS + 1))
if [[ ! -f "${WORK_DIR}/repo/.ingest-queue" ]]; then
  :
else
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: .ingest-queue should be removed after successful compile"
fi
# Timestamp should be updated
assert_file_exists "${WORK_DIR}/repo/.last-compile-timestamp" "timestamp updated after compile"

# ============================================================
echo "--- Test: my-drafts with to-compile status ---"
# ============================================================
setup_repo
cat > "${WORK_DIR}/repo/wiki/my-drafts/draft.md" <<'DRAFT'
---
title: "Test draft"
status: to-compile
---
Draft content.
DRAFT
cd "${WORK_DIR}/repo"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "wiki/my-drafts/draft.md" "my-drafts with to-compile detected"

# ============================================================
# Cleanup
# ============================================================
rm -rf "${WORK_DIR}"
teardown

report
