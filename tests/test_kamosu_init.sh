#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

setup
trap teardown EXIT

KB_NAME="test-init"
KB_DIR="${TEST_OUTPUT_BASE}/${KB_NAME}"

echo "  [1/4] Directory structure..."
kamosu_run kamosu-init --claude-oauth "${KB_NAME}" > /dev/null

assert_dir_exists "${KB_DIR}"
assert_dir_exists "${KB_DIR}/raw/papers"
assert_dir_exists "${KB_DIR}/raw/web-clips"
assert_dir_exists "${KB_DIR}/raw/repos"
assert_dir_exists "${KB_DIR}/wiki/_category"
assert_dir_exists "${KB_DIR}/wiki/concepts"
assert_dir_exists "${KB_DIR}/wiki/my-drafts"
assert_dir_exists "${KB_DIR}/outputs"
assert_file_exists "${KB_DIR}/CLAUDE.md"
assert_file_exists "${KB_DIR}/docker-compose.yml"
assert_file_exists "${KB_DIR}/docker-compose.claude-auth.yml"
assert_file_exists "${KB_DIR}/.gitignore"
assert_file_exists "${KB_DIR}/.env"
assert_file_exists "${KB_DIR}/.env.example"
assert_file_exists "${KB_DIR}/.kb-toolkit-version"
assert_file_exists "${KB_DIR}/wiki/_master_index.md"
assert_file_exists "${KB_DIR}/wiki/_cross_references.md"
assert_file_exists "${KB_DIR}/wiki/_log.md"

echo "  [2/4] Template variable substitution..."
assert_file_contains "${KB_DIR}/CLAUDE.md" "${KB_NAME}" "CLAUDE.md should contain KB name"

echo "  [3/4] Invalid KB name validation..."
kamosu_run_expect_fail kamosu-init --claude-oauth "-invalid" || \
    { echo "  ASSERT FAIL: should reject name starting with hyphen"; FAILURES=$((FAILURES + 1)); }
kamosu_run_expect_fail kamosu-init --claude-oauth "has spaces" || \
    { echo "  ASSERT FAIL: should reject name with spaces"; FAILURES=$((FAILURES + 1)); }
kamosu_run_expect_fail kamosu-init --claude-oauth "" 2>/dev/null || \
    { echo "  ASSERT FAIL: should reject empty name"; FAILURES=$((FAILURES + 1)); }

echo "  [4/4] Duplicate directory prevention..."
kamosu_run_expect_fail kamosu-init --claude-oauth "${KB_NAME}" || \
    { echo "  ASSERT FAIL: should reject duplicate KB name"; FAILURES=$((FAILURES + 1)); }

report
