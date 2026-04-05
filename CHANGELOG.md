# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- kamosu-shell: Claude Code interactive session launcher
- kamosu-compile: my-drafts/ `status: to-compile` support
- kamosu-init: interactive/non-interactive auth mode selection (--claude-oauth, --claude-bedrock)
- kamosu-init: --reconfigure for auth reconfiguration
- wiki/my-drafts/ user draft area (scaffold + protocol)
- CLAUDE.md, TASKS.md, DEVLOG.md for project management
- Makefile for build/test/release automation

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
- Templates (kb-claude.md.tmpl, docker-compose.yml.tmpl, .gitignore.tmpl, .env.example)

### Migration Required
- N/A (initial release)
