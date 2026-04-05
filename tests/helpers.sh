#!/usr/bin/env bash
# Shared test utilities

TEST_OUTPUT_BASE="/tmp/kamosu-test-$$"
DOCKER_IMAGE="kamosu:latest"
ASSERTIONS=0
FAILURES=0

setup() {
    mkdir -p "${TEST_OUTPUT_BASE}"
}

teardown() {
    if [[ -d "${TEST_OUTPUT_BASE}" ]]; then
        docker run --rm -v "${TEST_OUTPUT_BASE}:/output" "${DOCKER_IMAGE}" rm -rf /output/* 2>/dev/null || true
        rmdir "${TEST_OUTPUT_BASE}" 2>/dev/null || true
    fi
}

# Run kamosu command in Docker
kamosu_run() {
    docker run --rm -v "${TEST_OUTPUT_BASE}:/output" "${DOCKER_IMAGE}" "$@"
}

# Run kamosu command expecting failure
kamosu_run_expect_fail() {
    if docker run --rm -v "${TEST_OUTPUT_BASE}:/output" "${DOCKER_IMAGE}" "$@" 2>/dev/null; then
        return 1
    else
        return 0
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    ASSERTIONS=$((ASSERTIONS + 1))
    if [[ "${expected}" == "${actual}" ]]; then
        return 0
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${msg}"
        echo "    expected: '${expected}'"
        echo "    actual:   '${actual}'"
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-file should exist: ${path}}"
    ASSERTIONS=$((ASSERTIONS + 1))
    if [[ -e "${path}" ]]; then
        return 0
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${msg}"
        return 1
    fi
}

assert_dir_exists() {
    local path="$1"
    local msg="${2:-directory should exist: ${path}}"
    ASSERTIONS=$((ASSERTIONS + 1))
    if [[ -d "${path}" ]]; then
        return 0
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${msg}"
        return 1
    fi
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    local msg="${3:-file should contain pattern}"
    ASSERTIONS=$((ASSERTIONS + 1))
    if grep -q "${pattern}" "${path}" 2>/dev/null; then
        return 0
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${msg} (pattern: '${pattern}' not found in ${path})"
        return 1
    fi
}

assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    local msg="${3:-file should not contain pattern}"
    ASSERTIONS=$((ASSERTIONS + 1))
    if ! grep -q "${pattern}" "${path}" 2>/dev/null; then
        return 0
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${msg} (pattern: '${pattern}' found in ${path})"
        return 1
    fi
}

report() {
    if [[ ${FAILURES} -gt 0 ]]; then
        echo "  ${ASSERTIONS} assertions, ${FAILURES} failures"
        return 1
    else
        echo "  ${ASSERTIONS} assertions, all passed"
        return 0
    fi
}
