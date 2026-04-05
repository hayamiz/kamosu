#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DOCKER_IMAGE="kamosu:latest"

echo "  [1/4] Required commands in PATH..."
for cmd in kamosu-init kamosu-compile kamosu-shell git jq python3 node claude; do
    ASSERTIONS=$((ASSERTIONS + 1))
    if docker run --rm "${DOCKER_IMAGE}" which "${cmd}" > /dev/null 2>&1; then
        :
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: '${cmd}' not found in PATH"
    fi
done

echo "  [2/4] Script permissions..."
for script in kamosu-init kamosu-compile kamosu-shell entrypoint.sh; do
    ASSERTIONS=$((ASSERTIONS + 1))
    if docker run --rm "${DOCKER_IMAGE}" test -x "/opt/kamosu/scripts/${script}"; then
        :
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: /opt/kamosu/scripts/${script} not executable"
    fi
done

echo "  [3/4] File placement..."
for path in /opt/kamosu/claude-base.md /opt/kamosu/templates/kb-claude.md.tmpl /opt/kamosu/templates/docker-compose.yml.tmpl /opt/kamosu/templates/.env.example /opt/kamosu/VERSION; do
    ASSERTIONS=$((ASSERTIONS + 1))
    if docker run --rm "${DOCKER_IMAGE}" test -f "${path}"; then
        :
    else
        FAILURES=$((FAILURES + 1))
        echo "  ASSERT FAIL: ${path} not found"
    fi
done

echo "  [4/4] KB_TOOLKIT_VERSION environment variable..."
ASSERTIONS=$((ASSERTIONS + 1))
VERSION=$(docker run --rm "${DOCKER_IMAGE}" bash -c 'echo $KB_TOOLKIT_VERSION')
EXPECTED=$(cat VERSION | tr -d '[:space:]')
if [[ "${VERSION}" == "${EXPECTED}" ]]; then
    :
else
    FAILURES=$((FAILURES + 1))
    echo "  ASSERT FAIL: KB_TOOLKIT_VERSION expected '${EXPECTED}', got '${VERSION}'"
fi

report
