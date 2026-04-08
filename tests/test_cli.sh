#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CLI="${SCRIPT_DIR}/../cli/kamosu"
WORK_DIR="/tmp/kamosu-cli-test-$$"

setup
mkdir -p "${WORK_DIR}"

# Create a mock docker that logs its invocations instead of running containers
MOCK_BIN="${WORK_DIR}/mock-bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "${KAMOSU_MOCK_LOG}"

# Handle "docker info" (used by require_docker)
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi

# Handle "docker compose version" (used by detect_compose_cmd)
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "version" ]]; then
  echo "Docker Compose version v2.40.0"
  exit 0
fi

# Handle "docker images" (used by cmd_version)
if [[ "${1:-}" == "images" ]]; then
  echo "abc123"
  exit 0
fi

# Handle "docker inspect" (used by check_version_compat and cmd_migrate)
if [[ "${1:-}" == "inspect" ]]; then
  echo "0.2.0"
  exit 0
fi

# Handle "docker run --rm --entrypoint cat" (used by read_prompt)
if [[ "${1:-}" == "run" ]] && [[ "$*" == *"--entrypoint cat"* ]]; then
  # Return mock prompt content
  echo "mock prompt content"
  exit 0
fi

# Handle "docker compose run" (used by compose_run -> docker_claude)
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "run" ]]; then
  exit 0
fi

# Handle "docker pull"
if [[ "${1:-}" == "pull" ]]; then
  exit 0
fi

exit 0
MOCK
chmod +x "${MOCK_BIN}/docker"

# Mock git (for commands that use git)
cat > "${MOCK_BIN}/git" <<'MOCK'
#!/usr/bin/env bash
echo "git $*" >> "${KAMOSU_MOCK_LOG}"

# Handle "git rev-parse --is-inside-work-tree"
if [[ "${1:-}" == "rev-parse" ]] && [[ "${2:-}" == "--is-inside-work-tree" ]]; then
  exit 0
fi

# Handle "git remote -v"
if [[ "${1:-}" == "remote" ]]; then
  echo "origin	https://github.com/test/repo.git (fetch)"
  exit 0
fi

# Handle "git branch --show-current"
if [[ "${1:-}" == "branch" ]] && [[ "${2:-}" == "--show-current" ]]; then
  echo "main"
  exit 0
fi

# Handle "git pull"
if [[ "${1:-}" == "pull" ]]; then
  exit 0
fi

# Handle "git diff --quiet"
if [[ "${1:-}" == "diff" ]]; then
  exit 0
fi

# Handle "git add", "git commit", "git push"
exit 0
MOCK
chmod +x "${MOCK_BIN}/git"

export KAMOSU_MOCK_LOG="${WORK_DIR}/mock-calls.log"

run_cli() {
  > "${KAMOSU_MOCK_LOG}"  # clear log
  PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@"
}

run_cli_expect_fail() {
  > "${KAMOSU_MOCK_LOG}"
  if PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@" 2>/dev/null; then
    return 1
  else
    return 0
  fi
}

run_cli_capture() {
  > "${KAMOSU_MOCK_LOG}"
  PATH="${MOCK_BIN}:${PATH}" bash "${CLI}" "$@" 2>&1
}

# ============================================================
echo "--- Test: help (no args) ---"
# ============================================================
output="$(run_cli_capture)"
assert_file_contains <(echo "$output") "kamosu — LLM-powered knowledge base toolkit" "help output shows title"
assert_file_contains <(echo "$output") "kamosu <command>" "help output shows usage"

# ============================================================
echo "--- Test: help command ---"
# ============================================================
output="$(run_cli_capture help)"
assert_file_contains <(echo "$output") "kamosu <command>" "help command shows usage"

# ============================================================
echo "--- Test: --help flag ---"
# ============================================================
output="$(run_cli_capture --help)"
assert_file_contains <(echo "$output") "kamosu <command>" "--help shows usage"

# ============================================================
echo "--- Test: unknown command ---"
# ============================================================
run_cli_expect_fail nosuchcommand
assert_eq 0 $? "unknown command exits with error"

# ============================================================
echo "--- Test: version (outside data repo) ---"
# ============================================================
cd "${WORK_DIR}"
output="$(run_cli_capture version)"
assert_file_contains <(echo "$output") "kamosu CLI" "version shows CLI version"

# ============================================================
echo "--- Test: version (inside data repo) ---"
# ============================================================
echo "0.2.0" > "${WORK_DIR}/.kamosu-version"
cd "${WORK_DIR}"
output="$(run_cli_capture version)"
assert_file_contains <(echo "$output") "kamosu CLI" "version shows CLI version in data repo"
assert_file_contains <(echo "$output") "Data repo pinned to: 0.2.0" "version shows pinned version"
rm "${WORK_DIR}/.kamosu-version"

# ============================================================
echo "--- Test: init routes to docker run ---"
# ============================================================
cd "${WORK_DIR}"
run_cli init my-kb
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker run --rm -it -e HOST_UID -e HOST_GID -v" "init calls docker run with HOST_UID/HOST_GID"
assert_file_contains "${KAMOSU_MOCK_LOG}" "kamosu-init my-kb" "init passes kb-name"
assert_file_contains "${KAMOSU_MOCK_LOG}" "hayamiz/kamosu:latest" "init uses latest tag"

# ============================================================
echo "--- Test: init --help does not call docker run ---"
# ============================================================
cd "${WORK_DIR}"
output="$(run_cli_capture init --help)"
assert_file_contains <(echo "$output") "Usage: kamosu init" "init --help shows usage"
if grep -q "docker run" "${KAMOSU_MOCK_LOG}" 2>/dev/null; then
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: init --help should not call docker run"
else
  ASSERTIONS=$((ASSERTIONS + 1))
fi

# ============================================================
echo "--- Test: compile requires data repo ---"
# ============================================================
cd "${WORK_DIR}"
rm -f "${WORK_DIR}/.kamosu-version"
run_cli_expect_fail compile
assert_eq 0 $? "compile fails outside data repo"

# ============================================================
echo "--- Test: compile --dry-run with no files ---"
# ============================================================
echo "0.2.0" > "${WORK_DIR}/.kamosu-version"
mkdir -p "${WORK_DIR}/raw" "${WORK_DIR}/wiki"
cd "${WORK_DIR}"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "No new or updated files" "compile --dry-run reports no files"
# Should NOT call docker (no Docker needed for dry-run)
if grep -q "docker compose run" "${KAMOSU_MOCK_LOG}" 2>/dev/null; then
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: compile --dry-run should not invoke Docker"
else
  ASSERTIONS=$((ASSERTIONS + 1))
fi

# ============================================================
echo "--- Test: compile --dry-run detects new files ---"
# ============================================================
echo "test content" > "${WORK_DIR}/raw/test-paper.txt"
cd "${WORK_DIR}"
output="$(run_cli_capture compile --dry-run)"
assert_file_contains <(echo "$output") "raw/test-paper.txt" "compile --dry-run detects new file"
assert_file_contains <(echo "$output") "Dry run complete" "compile --dry-run shows completion"
rm "${WORK_DIR}/raw/test-paper.txt"

# ============================================================
echo "--- Test: compile invokes Claude via Docker ---"
# ============================================================
echo "test content" > "${WORK_DIR}/raw/test-paper.txt"
cd "${WORK_DIR}"
run_cli compile
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb claude" "compile invokes claude via docker compose"
assert_file_contains "${KAMOSU_MOCK_LOG}" "git pull" "compile runs git pull on host"
assert_file_contains "${KAMOSU_MOCK_LOG}" "git add" "compile runs git add on host"
rm -f "${WORK_DIR}/raw/test-paper.txt" "${WORK_DIR}/.ingest-queue" "${WORK_DIR}/.last-compile-timestamp"

# ============================================================
echo "--- Test: compile --help ---"
# ============================================================
output="$(run_cli_capture compile --help)"
assert_file_contains <(echo "$output") "Usage: kamosu compile" "compile --help shows usage"
assert_file_contains <(echo "$output") "resume" "compile --help shows --resume option"

# ============================================================
echo "--- Test: lint invokes Claude via Docker ---"
# ============================================================
cd "${WORK_DIR}"
run_cli lint
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb claude" "lint invokes claude via docker compose"

# ============================================================
echo "--- Test: lint --help ---"
# ============================================================
output="$(run_cli_capture lint --help)"
assert_file_contains <(echo "$output") "Usage: kamosu lint" "lint --help shows usage"

# ============================================================
echo "--- Test: search routes to Docker python3 ---"
# ============================================================
cd "${WORK_DIR}"
run_cli search "query execution"
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb python3" "search invokes python3 via docker compose"

# ============================================================
echo "--- Test: search --help ---"
# ============================================================
output="$(run_cli_capture search --help)"
assert_file_contains <(echo "$output") "Usage: kamosu search" "search --help shows usage"

# ============================================================
echo "--- Test: shell routes to Docker claude ---"
# ============================================================
cd "${WORK_DIR}"
run_cli shell -p "hello"
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb claude -p hello" "shell invokes claude via docker compose"

# ============================================================
echo "--- Test: shell --help ---"
# ============================================================
output="$(run_cli_capture shell --help)"
assert_file_contains <(echo "$output") "Usage: kamosu shell" "shell --help shows usage"

# ============================================================
echo "--- Test: promote --list (no Docker needed) ---"
# ============================================================
echo "0.2.0" > "${WORK_DIR}/.kamosu-version"
mkdir -p "${WORK_DIR}/wiki"
rm -rf "${WORK_DIR}/outputs"
cd "${WORK_DIR}"
output="$(run_cli_capture promote --list)"
assert_file_contains <(echo "$output") "No outputs/" "promote --list without outputs/"
# Should NOT call docker
if grep -q "docker compose run" "${KAMOSU_MOCK_LOG}" 2>/dev/null; then
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: promote --list should not invoke Docker"
else
  ASSERTIONS=$((ASSERTIONS + 1))
fi

# ============================================================
echo "--- Test: promote --help ---"
# ============================================================
output="$(run_cli_capture promote --help)"
assert_file_contains <(echo "$output") "Usage: kamosu promote" "promote --help shows usage"

# ============================================================
echo "--- Test: migrate --help ---"
# ============================================================
output="$(run_cli_capture migrate --help)"
assert_file_contains <(echo "$output") "Usage: kamosu migrate" "migrate --help shows usage"

# ============================================================
echo "--- Test: update pulls image ---"
# ============================================================
cd "${WORK_DIR}"
echo "0.2.0" > "${WORK_DIR}/.kamosu-version"
run_cli update
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker pull hayamiz/kamosu:0.2.0" "update pulls pinned image"

# ============================================================
echo "--- Test: update --help ---"
# ============================================================
output="$(run_cli_capture update --help)"
assert_file_contains <(echo "$output") "Usage: kamosu update" "update --help shows usage"

# ============================================================
echo "--- Test: Docker not installed ---"
# ============================================================
# shell command requires Docker early, so it's a good test target
echo "0.2.0" > "${WORK_DIR}/.kamosu-version"
mkdir -p "${WORK_DIR}/wiki"
cd "${WORK_DIR}"
NO_DOCKER_BIN="${WORK_DIR}/no-docker-bin"
mkdir -p "${NO_DOCKER_BIN}"
cat > "${NO_DOCKER_BIN}/docker" <<'NODOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  exit 1
fi
exit 0
NODOCK
chmod +x "${NO_DOCKER_BIN}/docker"
output="$(PATH="${NO_DOCKER_BIN}:/usr/bin:/bin" bash "${CLI}" shell 2>&1 || true)"
if echo "$output" | grep -q "Docker daemon is not running"; then
  ASSERTIONS=$((ASSERTIONS + 1))
else
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ASSERT FAIL: should report Docker daemon not running (got: ${output})"
fi

# ============================================================
# Cleanup
# ============================================================
rm -rf "${WORK_DIR}"
teardown

report
