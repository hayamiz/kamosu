#!/usr/bin/env bash
set -euo pipefail

readonly HOST_UID="${HOST_UID:-0}"
readonly HOST_GID="${HOST_GID:-0}"

# Create non-root user matching host UID/GID to avoid root-owned files on bind mounts
if [[ "${HOST_UID}" -ne 0 ]]; then
    groupadd -o -g "${HOST_GID}" kamosu 2>/dev/null || true
    useradd -o -u "${HOST_UID}" -g "${HOST_GID}" -m -d /home/kamosu -s /bin/bash kamosu 2>/dev/null || true
    export HOME=/home/kamosu
fi

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

# Version compatibility check (warn only, don't block)
if [[ -f "/workspace/.kamosu-version" ]]; then
    DATA_VERSION=$(cat /workspace/.kamosu-version | tr -d '[:space:]')
    IMAGE_VERSION="${KB_TOOLKIT_VERSION:-unknown}"
    if [[ "${IMAGE_VERSION}" != "unknown" ]] && [[ "${DATA_VERSION}" != "${IMAGE_VERSION}" ]]; then
        # Simple string comparison — works for semver in most cases
        if [[ "${DATA_VERSION}" > "${IMAGE_VERSION}" ]]; then
            echo "[entrypoint] ERROR: Data version (${DATA_VERSION}) is newer than image version (${IMAGE_VERSION}). Update the Docker image." >&2
        else
            echo "[entrypoint] WARNING: Data version (${DATA_VERSION}) differs from image version (${IMAGE_VERSION}). Run 'kamosu-migrate' to update." >&2
        fi
    fi
fi

# Drop privileges if non-root user was requested
if [[ "${HOST_UID}" -ne 0 ]]; then
    # Fix ownership of credential files so the non-root user can read them
    chown -R "${HOST_UID}:${HOST_GID}" "${HOME}/.claude" 2>/dev/null || true
    chown "${HOST_UID}:${HOST_GID}" "${HOME}/.claude.json" 2>/dev/null || true
    exec gosu kamosu "$@"
else
    exec "$@"
fi
