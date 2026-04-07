#!/usr/bin/env bash
set -euo pipefail

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
# Log the full command for assertion
echo "docker $*" >> "${KAMOSU_MOCK_LOG}"

# Handle "docker info" (used by require_docker)
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi

# Handle "docker images" (used by cmd_version)
if [[ "${1:-}" == "images" ]]; then
  echo "abc123"
  exit 0
fi

exit 0
MOCK
chmod +x "${MOCK_BIN}/docker"

# Mock docker compose as a separate handler (docker invokes compose as a subcommand)
# Override docker to also handle "compose" subcommand
cat > "${MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "${KAMOSU_MOCK_LOG}"

if [[ "${1:-}" == "info" ]]; then
  exit 0
fi

if [[ "${1:-}" == "images" ]]; then
  echo "abc123"
  exit 0
fi

exit 0
MOCK
chmod +x "${MOCK_BIN}/docker"

export KAMOSU_MOCK_LOG="${WORK_DIR}/docker-calls.log"

run_cli() {
  # Prepend mock bin to PATH so our mock docker is used
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
echo "0.2.0" > "${WORK_DIR}/.kb-toolkit-version"
cd "${WORK_DIR}"
output="$(run_cli_capture version)"
assert_file_contains <(echo "$output") "kamosu CLI" "version shows CLI version in data repo"
assert_file_contains <(echo "$output") "Data repo pinned to: 0.2.0" "version shows pinned version"
rm "${WORK_DIR}/.kb-toolkit-version"

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
# The mock log should only have empty or no docker run call
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
rm -f "${WORK_DIR}/.kb-toolkit-version"
run_cli_expect_fail compile
assert_eq 0 $? "compile fails outside data repo"

# ============================================================
echo "--- Test: compile routes to docker compose run ---"
# ============================================================
echo "0.1.0" > "${WORK_DIR}/.kb-toolkit-version"
cd "${WORK_DIR}"
run_cli compile --dry-run
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-compile --dry-run" "compile calls docker compose run"

# ============================================================
echo "--- Test: compile --help ---"
# ============================================================
output="$(run_cli_capture compile --help)"
assert_file_contains <(echo "$output") "Usage: kamosu compile" "compile --help shows usage"

# ============================================================
echo "--- Test: lint routes to docker compose run ---"
# ============================================================
cd "${WORK_DIR}"
run_cli lint --fix
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-lint --fix" "lint calls docker compose run"

# ============================================================
echo "--- Test: lint --help ---"
# ============================================================
output="$(run_cli_capture lint --help)"
assert_file_contains <(echo "$output") "Usage: kamosu lint" "lint --help shows usage"

# ============================================================
echo "--- Test: search routes to docker compose run ---"
# ============================================================
cd "${WORK_DIR}"
run_cli search "query execution"
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-search query execution" "search calls docker compose run"

# ============================================================
echo "--- Test: search --help ---"
# ============================================================
output="$(run_cli_capture search --help)"
assert_file_contains <(echo "$output") "Usage: kamosu search" "search --help shows usage"

# ============================================================
echo "--- Test: shell routes to docker compose run ---"
# ============================================================
cd "${WORK_DIR}"
run_cli shell -p "hello"
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-shell -p hello" "shell calls docker compose run"

# ============================================================
echo "--- Test: shell --help ---"
# ============================================================
output="$(run_cli_capture shell --help)"
assert_file_contains <(echo "$output") "Usage: kamosu shell" "shell --help shows usage"

# ============================================================
echo "--- Test: migrate routes to docker compose run ---"
# ============================================================
cd "${WORK_DIR}"
run_cli migrate --dry-run
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker compose run --rm kb kamosu-migrate --dry-run" "migrate calls docker compose run"

# ============================================================
echo "--- Test: migrate --help ---"
# ============================================================
output="$(run_cli_capture migrate --help)"
assert_file_contains <(echo "$output") "Usage: kamosu migrate" "migrate --help shows usage"

# ============================================================
echo "--- Test: update pulls image ---"
# ============================================================
cd "${WORK_DIR}"
run_cli update
assert_file_contains "${KAMOSU_MOCK_LOG}" "docker pull hayamiz/kamosu:0.1.0" "update pulls pinned image"

# ============================================================
echo "--- Test: update --help ---"
# ============================================================
output="$(run_cli_capture update --help)"
assert_file_contains <(echo "$output") "Usage: kamosu update" "update --help shows usage"

# ============================================================
echo "--- Test: Docker not installed ---"
# ============================================================
cd "${WORK_DIR}"
# Create a PATH without docker by shadowing it with a script that fails
NO_DOCKER_BIN="${WORK_DIR}/no-docker-bin"
mkdir -p "${NO_DOCKER_BIN}"
cat > "${NO_DOCKER_BIN}/docker" <<'NODOCK'
#!/usr/bin/env bash
# Simulate docker present but daemon not running
if [[ "${1:-}" == "info" ]]; then
  exit 1
fi
exit 0
NODOCK
chmod +x "${NO_DOCKER_BIN}/docker"
output="$(PATH="${NO_DOCKER_BIN}:/usr/bin:/bin" bash "${CLI}" compile 2>&1 || true)"
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
