#!/usr/bin/env bash
set -euo pipefail

readonly CLAUDE_HOST_DIR="/tmp/.claude-host"
readonly CLAUDE_TARGET_DIR="${HOME}/.claude"

# Copy host Claude credentials into the container if mounted
if [[ -f "${CLAUDE_HOST_DIR}/.credentials.json" ]]; then
    mkdir -p "${CLAUDE_TARGET_DIR}"
    cp "${CLAUDE_HOST_DIR}/.credentials.json" "${CLAUDE_TARGET_DIR}/.credentials.json"
    echo "[entrypoint] Claude OAuth credentials loaded from host."
fi

# Ensure onboarding flag exists (prevents first-time setup wizard)
if [[ -f "${CLAUDE_TARGET_DIR}/.credentials.json" ]] && [[ ! -f "${HOME}/.claude.json" ]]; then
    echo '{"completedOnboarding":true}' > "${HOME}/.claude.json"
    echo "[entrypoint] Created .claude.json (onboarding flag)."
fi

exec "$@"
