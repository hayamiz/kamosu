#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PROMOTE_SCRIPT="${SCRIPT_DIR}/../scripts/kamosu-promote"
WORK_DIR="/tmp/kamosu-promote-test-$$"
OUTPUT_FILE="${WORK_DIR}/test-output.txt"

setup
mkdir -p "${WORK_DIR}"

# Helper: create a minimal data repo structure
create_data_repo() {
    local dir="$1"
    mkdir -p "${dir}/raw/papers" "${dir}/wiki/concepts" "${dir}/wiki/_category" "${dir}/wiki/my-drafts" "${dir}/outputs"
    echo "# Test KB" > "${dir}/CLAUDE.md"
    echo "0.1.0" > "${dir}/.kb-toolkit-version"
    cat > "${dir}/wiki/_master_index.md" <<'INDEX'
# Master Index

Last updated: 2026-04-06

## Categories

| Category | Articles | Summary |
|----------|----------|---------|

## Statistics
- Total articles: 0
- Total categories: 0
- Last compiled: 2026-04-06T00:00:00Z
INDEX
}

# Helper: capture output to file for assertions
capture() {
    "$@" > "${OUTPUT_FILE}" 2>&1 || true
}

# ============================================================
echo "--- Test: --help shows usage ---"
# ============================================================
capture bash "${PROMOTE_SCRIPT}" --help
assert_file_contains "${OUTPUT_FILE}" "Usage: kamosu-promote" "--help shows usage"
assert_file_contains "${OUTPUT_FILE}" "dry-run" "--help mentions --dry-run"
assert_file_contains "${OUTPUT_FILE}" "unpromoted" "--help mentions --list"

# ============================================================
echo "--- Test: error outside data repo ---"
# ============================================================
cd "${WORK_DIR}"
rm -f CLAUDE.md
capture bash "${PROMOTE_SCRIPT}" outputs/test.md
assert_file_contains "${OUTPUT_FILE}" "CLAUDE.md not found" "errors outside data repo"

# ============================================================
echo "--- Test: error on non-existent file ---"
# ============================================================
REPO_DIR="${WORK_DIR}/repo-nonexist"
create_data_repo "${REPO_DIR}"
cd "${REPO_DIR}"
capture bash "${PROMOTE_SCRIPT}" outputs/does-not-exist.md
assert_file_contains "${OUTPUT_FILE}" "File not found" "errors on non-existent file"

# ============================================================
echo "--- Test: error with no files specified ---"
# ============================================================
cd "${REPO_DIR}"
capture bash "${PROMOTE_SCRIPT}"
assert_file_contains "${OUTPUT_FILE}" "No files specified" "errors when no files specified"

# ============================================================
echo "--- Test: --list with no outputs ---"
# ============================================================
REPO_DIR_EMPTY="${WORK_DIR}/repo-empty"
create_data_repo "${REPO_DIR_EMPTY}"
cd "${REPO_DIR_EMPTY}"
rmdir "${REPO_DIR_EMPTY}/outputs"
capture bash "${PROMOTE_SCRIPT}" --list
assert_file_contains "${OUTPUT_FILE}" "No outputs/ directory" "--list handles missing outputs/"

# ============================================================
echo "--- Test: --list shows unpromoted files ---"
# ============================================================
REPO_DIR_LIST="${WORK_DIR}/repo-list"
create_data_repo "${REPO_DIR_LIST}"
cd "${REPO_DIR_LIST}"
echo "# Analysis A" > outputs/analysis-a.md
echo "# Analysis B" > outputs/analysis-b.md
capture bash "${PROMOTE_SCRIPT}" --list
assert_file_contains "${OUTPUT_FILE}" "analysis-a.md" "--list shows unpromoted file a"
assert_file_contains "${OUTPUT_FILE}" "analysis-b.md" "--list shows unpromoted file b"

# ============================================================
echo "--- Test: --list filters promoted files ---"
# ============================================================
cd "${REPO_DIR_LIST}"
echo "2026-04-06T00:00:00Z	outputs/analysis-a.md" > .promote-history
capture bash "${PROMOTE_SCRIPT}" --list
assert_file_not_contains "${OUTPUT_FILE}" "analysis-a.md" "--list hides promoted file"
assert_file_contains "${OUTPUT_FILE}" "analysis-b.md" "--list still shows unpromoted file"

# ============================================================
echo "--- Test: --dry-run does not write .promote-history ---"
# ============================================================
REPO_DIR_DRYRUN="${WORK_DIR}/repo-dryrun"
create_data_repo "${REPO_DIR_DRYRUN}"
cd "${REPO_DIR_DRYRUN}"
echo "# Test output" > outputs/test-output.md

# Mock claude
MOCK_BIN="${WORK_DIR}/mock-bin"
mkdir -p "${MOCK_BIN}"
cat > "${MOCK_BIN}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "Mock claude: would process files"
exit 0
MOCK
chmod +x "${MOCK_BIN}/claude"

PATH="${MOCK_BIN}:${PATH}" bash "${PROMOTE_SCRIPT}" --dry-run outputs/test-output.md >/dev/null 2>&1 || true
if [[ -f .promote-history ]]; then
    ASSERTIONS=$((ASSERTIONS + 1))
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: --dry-run should not create .promote-history"
else
    ASSERTIONS=$((ASSERTIONS + 1))
fi

# ============================================================
echo "--- Test: full promote records history (mock claude) ---"
# ============================================================
REPO_DIR_FULL="${WORK_DIR}/repo-full"
create_data_repo "${REPO_DIR_FULL}"
cd "${REPO_DIR_FULL}"
echo "# Full test" > outputs/full-test.md

# Init git so the script doesn't fail on git commands
git init -q .
git add -A
git commit -q -m "init"

PATH="${MOCK_BIN}:${PATH}" bash "${PROMOTE_SCRIPT}" outputs/full-test.md >/dev/null 2>&1 || true
assert_file_exists ".promote-history" "promote creates .promote-history"
assert_file_contains ".promote-history" "outputs/full-test.md" ".promote-history contains promoted file"

# ============================================================
echo "--- Test: CLI promote --help ---"
# ============================================================
CLI="${SCRIPT_DIR}/../cli/kamosu"
CLI_MOCK_BIN="${WORK_DIR}/cli-mock-bin"
mkdir -p "${CLI_MOCK_BIN}"
cat > "${CLI_MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "${KAMOSU_MOCK_LOG:-/dev/null}"
if [[ "${1:-}" == "info" ]]; then exit 0; fi
exit 0
MOCK
chmod +x "${CLI_MOCK_BIN}/docker"

export KAMOSU_MOCK_LOG="${WORK_DIR}/docker-calls.log"
PATH="${CLI_MOCK_BIN}:${PATH}" bash "${CLI}" promote --help > "${OUTPUT_FILE}" 2>&1
assert_file_contains "${OUTPUT_FILE}" "Usage: kamosu promote" "CLI promote --help shows usage"

# ============================================================
echo "--- Test: CLI promote routes to docker compose ---"
# ============================================================
cd "${REPO_DIR_FULL}"
> "${KAMOSU_MOCK_LOG}"
PATH="${CLI_MOCK_BIN}:${PATH}" bash "${CLI}" promote outputs/full-test.md >/dev/null 2>&1 || true
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-promote" "CLI promote calls docker compose"

# ============================================================
# Cleanup
# ============================================================
rm -rf "${WORK_DIR}"
teardown

report
