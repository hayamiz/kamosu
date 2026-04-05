# kamosu — Toolkit Development Guide

## Project Overview

kamosu is a Docker-based toolkit that leverages LLMs to build and maintain research knowledge bases. See [kamosu-design.md](kamosu-design.md) for detailed design.

## Architecture

- **Separation of tools and data**: This repository (toolkit repo) is distributed as a Docker image. User data is managed in a separate repository (data repo).
- **Docker image**: Ubuntu 24.04 + Node.js + Claude Code CLI + kamosu scripts
- **Templates**: Files in `templates/` are scaffolded into the data repository by `kamosu-init`

## Key Files

| File | Role |
|------|------|
| `kamosu-design.md` | Design document (must be updated on any design change) |
| `claude-base.md` | Shared LLM protocol for all KBs (compile, query, lint) |
| `Dockerfile` | Docker image definition for the toolkit |
| `scripts/kamosu-init` | Scaffolding generator for data repositories |
| `scripts/entrypoint.sh` | Authentication setup at container startup |
| `templates/kb-claude.md.tmpl` | CLAUDE.md template for data repositories |
| `templates/docker-compose.yml.tmpl` | Compose template for data repositories |
| `VERSION` | Semantic version (currently 0.1.0) |
| `TASKS.md` | Implementation tasks and progress tracking |
| `DEVLOG.md` | Log of discoveries, decisions, and insights during development |

## Development Rules

### Language
- **All documentation (CLAUDE.md, README.md), code comments, and program messages must be written in English.**

### Design Document Sync
- When adding features or changing the design, **always update `kamosu-design.md`**
- `kamosu-design.md` is the Single Source of Truth for specifications and design

### Task Management (TASKS.md)
- Use `TASKS.md` to track implementation tasks and progress
- New tasks can be added at any time. Tasks discovered during implementation go in the Backlog section
- Mark completed tasks with `[x]` and add the completion date
- `kamosu-design.md` should only contain phase objectives and feature definitions — no checkboxes

### Development Log (DEVLOG.md)
- When you encounter the following during implementation, **add an entry to `DEVLOG.md`**:
  - **decision**: Design decisions and their rationale
  - **discovery**: Facts learned during implementation (library behavior, environment constraints, etc.)
  - **gotcha**: Pain points and their solutions
  - **idea**: Ideas for future improvements
- Format: `## YYYY-MM-DD | category | Title` + body
- Newest entries at the top

### Coding Conventions
- Bash scripts must start with `set -euo pipefail`
- All scripts must implement a `--help` option
- Error messages must be specific and actionable

### Template Naming Convention
- Template files use the `*.tmpl` extension (e.g., `docker-compose.yml.tmpl`)
- **Note**: `templates/kb-claude.md.tmpl` is the CLAUDE.md template for data repositories — it is separate from this project's `CLAUDE.md` (this file)

### Docker Image
- Local build: `docker build -t kamosu:latest .`
- Test: `docker run --rm -v $(pwd)/test-output:/output kamosu:latest kamosu-init test-kb`

### Authentication Modes
- **Host OAuth inheritance** (default): Mount the host's `~/.claude/` into the container
- **AWS Bedrock**: Set `AWS_PROFILE` and `AWS_REGION` in `.env`

## References

- [LLM Wiki — Andrej Karpathy](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — Inspiration for kamosu's design. Pattern where LLMs incrementally build and maintain a wiki.
