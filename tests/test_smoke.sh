#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

setup
trap teardown EXIT

KB_NAME="smoke-test"
KB_DIR="${TEST_OUTPUT_BASE}/${KB_NAME}"

echo "  [1/3] End-to-end: init with OAuth..."
kamosu_run kamosu-init --claude-oauth "${KB_NAME}" > /dev/null
assert_dir_exists "${KB_DIR}"
assert_file_contains "${KB_DIR}/docker-compose.yml" ".claude-host:ro" "OAuth compose should mount .claude-host"
assert_file_contains "${KB_DIR}/docker-compose.yml" ".claude-host.json:ro" "OAuth compose should mount .claude.json"

echo "  [2/3] End-to-end: init with Bedrock profile..."
kamosu_run kamosu-init --claude-bedrock --aws-profile testprof --aws-region us-west-2 "smoke-bedrock" > /dev/null
assert_file_contains "${TEST_OUTPUT_BASE}/smoke-bedrock/.kamosu-config" "AWS_PROFILE=testprof"
assert_file_contains "${TEST_OUTPUT_BASE}/smoke-bedrock/.kamosu-config" "AWS_REGION=us-west-2"

echo "  [3/3] End-to-end: init with Bedrock IAM Role..."
kamosu_run kamosu-init --claude-bedrock --aws-region ap-northeast-1 "smoke-iam" > /dev/null
assert_file_contains "${TEST_OUTPUT_BASE}/smoke-iam/.kamosu-config" "AWS_REGION=ap-northeast-1"
assert_file_not_contains "${TEST_OUTPUT_BASE}/smoke-iam/.kamosu-config" "AWS_PROFILE" ".env should not have AWS_PROFILE for IAM Role mode"

report
