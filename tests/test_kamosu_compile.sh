#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

setup
trap teardown EXIT

KB_NAME="test-compile"
KB_DIR="${TEST_OUTPUT_BASE}/kb-${KB_NAME}"

# Initialize a KB for testing
kamosu_run kamosu-init --claude-oauth "${KB_NAME}" > /dev/null

echo "  [1/4] --dry-run with no files..."
ASSERTIONS=$((ASSERTIONS + 1))
RESULT=$(docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" kamosu-compile --dry-run 2>&1)
if echo "${RESULT}" | grep -q "No new or updated files"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: dry-run with empty raw/ should report no files. Got: ${RESULT}"
fi

echo "  [2/4] --dry-run detects new files..."
# Add a test file to raw/
docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" \
    bash -c 'echo "test content" > raw/papers/test-paper.txt'

ASSERTIONS=$((ASSERTIONS + 1))
RESULT=$(docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" kamosu-compile --dry-run 2>&1)
if echo "${RESULT}" | grep -q "raw/papers/test-paper.txt"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: dry-run should detect new file. Got: ${RESULT}"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if echo "${RESULT}" | grep -q "Dry run complete"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: dry-run should print completion message. Got: ${RESULT}"
fi

echo "  [3/4] --file with nonexistent file..."
ASSERTIONS=$((ASSERTIONS + 1))
if docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" kamosu-compile --file raw/nonexistent.pdf 2>/dev/null; then
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: --file with nonexistent file should fail"
fi

echo "  [4/4] .last-compile-timestamp based diff detection..."
# Create timestamp file, then verify the existing file is NOT detected
docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" \
    bash -c 'touch .last-compile-timestamp; sleep 1'

ASSERTIONS=$((ASSERTIONS + 1))
RESULT=$(docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" kamosu-compile --dry-run 2>&1)
if echo "${RESULT}" | grep -q "No new or updated files"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: files older than timestamp should not be detected. Got: ${RESULT}"
fi

# Add a newer file and verify it IS detected
docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" \
    bash -c 'echo "newer content" > raw/papers/newer-paper.txt'

ASSERTIONS=$((ASSERTIONS + 1))
RESULT=$(docker run --rm -v "${KB_DIR}:/workspace" -w /workspace "${DOCKER_IMAGE}" kamosu-compile --dry-run 2>&1)
if echo "${RESULT}" | grep -q "raw/papers/newer-paper.txt"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: file newer than timestamp should be detected. Got: ${RESULT}"
fi

# Old file should NOT appear
ASSERTIONS=$((ASSERTIONS + 1))
if echo "${RESULT}" | grep -q "test-paper.txt"; then
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: file older than timestamp should NOT be detected"
fi

report
