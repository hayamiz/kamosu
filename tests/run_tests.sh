#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
ERRORS=()

run_test() {
    local test_script="$1"
    local test_name
    test_name=$(basename "${test_script}" .sh)
    echo "=== Running: ${test_name} ==="
    if bash "${test_script}"; then
        echo "=== PASS: ${test_name} ==="
        PASS=$((PASS + 1))
    else
        echo "=== FAIL: ${test_name} ==="
        FAIL=$((FAIL + 1))
        ERRORS+=("${test_name}")
    fi
    echo ""
}

echo "kamosu test runner"
echo "=================="
echo ""

# Run all test_*.sh scripts in the tests directory
for test_file in "${SCRIPT_DIR}"/test_*.sh; do
    [[ -f "${test_file}" ]] || continue
    run_test "${test_file}"
done

echo "=================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do
        echo "  - ${e}"
    done
    exit 1
fi

echo "All tests passed."
exit 0
