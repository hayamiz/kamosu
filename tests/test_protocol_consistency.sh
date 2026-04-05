#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# This test verifies that the directory structure assumed by claude-base.md
# matches what kamosu-init actually generates.

setup
trap teardown EXIT

KB_NAME="test-protocol"
KB_DIR="${TEST_OUTPUT_BASE}/kb-${KB_NAME}"

kamosu_run kamosu-init --claude-oauth "${KB_NAME}" > /dev/null

CLAUDE_BASE="/workspaces/kamosu/claude-base.md"

echo "  [1/3] Directories referenced in claude-base.md exist in scaffold..."

# Extract directory paths from claude-base.md's directory structure diagram
# The protocol references: wiki/, wiki/_category/, wiki/concepts/, wiki/my-drafts/,
# wiki/_master_index.md, wiki/_cross_references.md, wiki/_log.md, raw/, outputs/
EXPECTED_DIRS=(
    "wiki"
    "wiki/_category"
    "wiki/concepts"
    "wiki/my-drafts"
    "raw"
    "outputs"
)

for dir in "${EXPECTED_DIRS[@]}"; do
    assert_dir_exists "${KB_DIR}/${dir}" "claude-base.md references ${dir}/ but kamosu-init didn't create it"
done

echo "  [2/3] Files referenced in claude-base.md exist in scaffold..."

EXPECTED_FILES=(
    "wiki/_master_index.md"
    "wiki/_cross_references.md"
    "wiki/_log.md"
    "CLAUDE.md"
)

for file in "${EXPECTED_FILES[@]}"; do
    assert_file_exists "${KB_DIR}/${file}" "claude-base.md references ${file} but kamosu-init didn't create it"
done

echo "  [3/3] claude-base.md directory diagram matches scaffold..."

# Verify the directory structure in claude-base.md mentions all key dirs
ASSERTIONS=$((ASSERTIONS + 1))
if grep -q '_master_index.md' "${CLAUDE_BASE}" && \
   grep -q '_category/' "${CLAUDE_BASE}" && \
   grep -q '_cross_references.md' "${CLAUDE_BASE}" && \
   grep -q '_log.md' "${CLAUDE_BASE}" && \
   grep -q 'concepts/' "${CLAUDE_BASE}" && \
   grep -q 'my-drafts/' "${CLAUDE_BASE}"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: claude-base.md directory diagram missing expected paths"
fi

# Verify kamosu-design.md data repo structure mentions my-drafts
ASSERTIONS=$((ASSERTIONS + 1))
if grep -q 'my-drafts/' "/workspaces/kamosu/kamosu-design.md"; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: kamosu-design.md missing my-drafts/ in data repo structure"
fi

report
