# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- kamosu-shell: Claude Code interactive session launcher
- kamosu-lint: wiki health check with --fix auto-correction
- kamosu-search: TF-IDF full-text search CLI (Python)
- kamosu-migrate: version migration with chain apply, --dry-run, --force, --to
- kamosu-compile: my-drafts/ `status: to-compile` support
- kamosu-init: interactive/non-interactive auth mode selection (--claude-oauth, --claude-bedrock)
- kamosu-init: --reconfigure for auth reconfiguration
- wiki/my-drafts/ user draft area (scaffold + protocol in claude-base.md Section 6)
- Version compatibility check in entrypoint.sh (warn on mismatch)
- migrate/ directory for version migration scripts
- release-check: migrate/ consistency validation
- CLAUDE.md, TASKS.md, DEVLOG.md for project management
- Makefile for build/test/release automation
- Test suite (6 suites, 65 assertions)

### Changed
- Dockerfile: replaced hardcoded KB_TOOLKIT_VERSION with ARG
- Renamed templates/CLAUDE.md.template to templates/kb-claude.md.tmpl
- kamosu-compile: lighter prompt (Claude Code reads CLAUDE.md automatically)

### Migration Required
- N/A

## [0.1.0] - 2026-04-05

### Added
- Initial release (Phase 1 Core MVP)
- Dockerfile (Ubuntu 24.04 + Claude Code + Python3)
- claude-base.md (compilation, query, lint protocols)
- kamosu-init (scaffolding generation)
- kamosu-compile (diff detection + Claude Code invocation + git commit)
- entrypoint.sh (OAuth credential handling in containers)
- Templates (kb-claude.md.tmpl, docker-compose.yml.tmpl, .gitignore.tmpl, .kamosu-config.example)

### Migration Required
- N/A (initial release)
