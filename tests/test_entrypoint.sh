#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DOCKER_IMAGE="kamosu:latest"
MOCK_CLAUDE_DIR="/tmp/kamosu-test-claude-$$"

setup
trap 'teardown; rm -rf "${MOCK_CLAUDE_DIR}"' EXIT

echo "  [1/3] Credential copy when present..."
# Create mock credential file
mkdir -p "${MOCK_CLAUDE_DIR}"
echo '{"token":"test-token"}' > "${MOCK_CLAUDE_DIR}/.credentials.json"

ASSERTIONS=$((ASSERTIONS + 1))
# entrypoint prints log lines to stdout, so grep for the actual content
RESULT=$(docker run --rm -v "${MOCK_CLAUDE_DIR}:/tmp/.claude-host:ro" "${DOCKER_IMAGE}" bash -c 'cat ~/.claude/.credentials.json 2>/dev/null || echo NOT_FOUND' 2>&1 | grep -v '^\[entrypoint\]')
if [[ "${RESULT}" == '{"token":"test-token"}' ]]; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: credentials not copied. Got: ${RESULT}"
fi

echo "  [2/3] Skip when no credentials..."
ASSERTIONS=$((ASSERTIONS + 1))
# Run without mounting credentials - should not error
if docker run --rm "${DOCKER_IMAGE}" echo "ok" > /dev/null 2>&1; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: entrypoint errored without credentials"
fi

echo "  [3/3] Onboarding flag generation..."
ASSERTIONS=$((ASSERTIONS + 1))
RESULT=$(docker run --rm -v "${MOCK_CLAUDE_DIR}:/tmp/.claude-host:ro" "${DOCKER_IMAGE}" bash -c 'cat ~/.claude.json 2>/dev/null || echo NOT_FOUND')
if echo "${RESULT}" | grep -q 'completedOnboarding'; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: .claude.json not generated. Got: ${RESULT}"
fi

report
