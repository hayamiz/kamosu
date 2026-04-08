# kamosu Architecture Redesign — Host-Centric vs Docker-Centric

## 1. Problem Statement

The current architecture runs **all script logic inside Docker containers**, delegating from the host CLI (`cli/kamosu`) via `docker compose run`. This causes several pain points:

### 1.1 Git Authentication in Docker

`kamosu-compile` and `kamosu-promote` execute `git pull` / `git push` inside the container. The container has no access to host SSH keys or Git credential helpers, so these operations fail:

```
[kamosu-compile] WARNING: Git pull failed. Continuing with local state.
```

Possible mitigations within the current design:
- **SSH agent forwarding**: Mount `SSH_AUTH_SOCK` into the container and install `ssh-agent` support. Requires `docker-compose.yml` changes and host socket path detection.
- **SSH key mounting**: Mount `~/.ssh/` read-only. Security concern — exposes private keys to container.
- **Git credential helper**: Mount `~/.gitconfig` and credential store. Varies by OS and helper type (macOS Keychain, Windows Credential Manager, `git-credential-cache`, etc.)
- **HTTPS token**: Pass a `GIT_TOKEN` environment variable. Only works for HTTPS remotes.

All of these are fragile, platform-dependent, and add configuration burden for users.

### 1.2 Tool Availability

Claude Code inside Docker can only use tools installed in the image. The current `--allowedTools` restriction (`Edit,Write,Read,Glob,Grep`) blocks Bash, meaning:
- PDF extraction requires `poppler-utils` or Python libraries pre-installed in the image
- Any new tool dependency requires a Docker image rebuild
- Users cannot extend tool availability without rebuilding the image

### 1.3 Docker Compose Compatibility

`docker compose run --rm` requires Docker Compose V2. Users with V1 (`docker-compose`) or unusual Docker installations encounter `unknown flag: --rm` errors. (Already partially mitigated by `compose_run()` helper.)

### 1.4 Startup Overhead

Every `kamosu compile` invocation spins up a new container (entrypoint credential copy, user creation, etc.). For frequent operations this adds noticeable latency.

---

## 2. Design Options

### Option A: Status Quo with Git Auth Plumbing

Keep all logic in Docker. Add SSH/Git credential forwarding to the container.

**Changes required:**
- `docker-compose.yml.tmpl`: Add conditional SSH agent socket mount, `~/.ssh` mount, `~/.gitconfig` mount
- `entrypoint.sh`: Detect and configure SSH agent, copy known_hosts
- `kamosu-init`: New auth options (`--git-ssh`, `--git-https-token`)
- `.env`: New variables (`GIT_AUTH_MODE`, `GIT_TOKEN`, etc.)
- `cli/kamosu`: Detect host SSH_AUTH_SOCK path and pass to Docker

**Pros:**
- Minimal architectural change — incremental improvement
- Docker encapsulation preserved — all tools and dependencies are version-locked in the image
- Reproducible environment across machines

**Cons:**
- SSH agent socket forwarding is platform-dependent (Linux: works natively; macOS: requires Docker Desktop socket proxy; Windows/WSL: complex)
- Multiple auth modes to test and maintain (SSH agent, SSH key mount, HTTPS token, credential helper)
- `.env` / `docker-compose.yml` grow more complex for each auth mode
- Does not solve the tool availability problem (1.2)
- Startup overhead remains (1.4)
- Users who "just have git working" on their host must now re-configure Git auth for Docker

### Option B: Host-Centric — Move Script Logic to Host CLI

Move all orchestration logic (git operations, file detection, timestamp management, queue writing) to `cli/kamosu`. Docker is used **only** for running `claude` commands and `python3` (search engine).

**Architecture change:**

```
BEFORE (current):
  Host CLI ──docker compose run──▶ Container [kamosu-compile]
                                     ├─ git pull
                                     ├─ file detection
                                     ├─ write .ingest-queue
                                     ├─ claude -p "..."
                                     ├─ git add/commit/push
                                     └─ timestamp update

AFTER (Option B):
  Host CLI [kamosu compile]
    ├─ git pull                     ← runs on host (native git auth)
    ├─ file detection               ← runs on host (bash find)
    ├─ write .ingest-queue          ← runs on host
    ├─ docker compose run claude    ← ONLY the claude invocation in Docker
    ├─ git add/commit/push          ← runs on host (native git auth)
    └─ timestamp update             ← runs on host
```

**Changes required:**
- `cli/kamosu`: Absorb logic from `kamosu-compile`, `kamosu-lint`, `kamosu-promote`, `kamosu-shell`, `kamosu-migrate` (the bash orchestration parts)
- `docker-compose.yml.tmpl`: Service definition simplified — just runs `claude` or `python3`
- `scripts/`: Reduced to thin `claude` invocation wrappers (or removed entirely, with prompts defined in `cli/kamosu`)
- Docker image: Still needed for `claude` CLI and `python3` search engine, but no longer for git, orchestration logic

**Pros:**
- **Git auth problem vanishes** — host git "just works" with whatever auth the user already has configured
- **Simpler Docker image** — fewer responsibilities, smaller attack surface
- **Tool availability improves** — Claude Code inside Docker can still be restricted, but host-side tools (PDF extractors, etc.) could be pre-processed before invoking Claude
- **Faster iteration** — changing orchestration logic doesn't require Docker image rebuild
- **Single-file distribution** — `cli/kamosu` becomes the primary codebase; users update by re-downloading one file
- **Reduced startup overhead** — Docker only starts for the Claude invocation step
- **Familiar mental model** — "kamosu is a CLI tool that calls Claude Code in Docker" is simpler than "kamosu runs everything in Docker"

**Cons:**
- **Host dependencies** — Requires `bash`, `git`, `find`, `date` on the host. These are nearly universal on Linux/macOS, but Windows users need WSL or Git Bash
- **cli/kamosu grows larger** — From ~350 lines to ~800-1000 lines. Still a single file, but more to maintain
- **Divergence risk** — Orchestration logic is no longer version-locked with the Docker image. If a new image version expects a different `.ingest-queue` format, the host CLI must be updated too
- **Two update paths** — Users must update both the CLI (`curl` re-install) and the Docker image (`kamosu update`). Version mismatch is possible
- **Search engine** — `kamosu-search` depends on Python + TF-IDF libraries in Docker. This still needs Docker unless we ship a standalone binary

### Option C: Hybrid — Host Orchestration + Docker for LLM and Search Only

A refinement of Option B that makes the boundary between host and Docker explicit and minimal.

**Architecture:**

```
Host CLI [kamosu compile]
  ├─ git pull                         ← host
  ├─ file detection                   ← host
  ├─ write .ingest-queue              ← host
  ├─ docker run ... claude -p "..."   ← Docker (LLM only)
  ├─ git add/commit/push             ← host
  └─ timestamp update                ← host

Host CLI [kamosu search]
  └─ docker run ... python3 searcher.py  ← Docker (search engine)

Host CLI [kamosu shell]
  └─ docker run ... claude               ← Docker (interactive LLM)

Host CLI [kamosu lint]
  ├─ docker run ... claude -p "..."   ← Docker (LLM only)
  └─ git add/commit (if --fix)       ← host

Host CLI [kamosu migrate]
  ├─ version check                    ← host
  ├─ dirty check                      ← host
  ├─ docker run ... bash migrate.sh   ← Docker (migration scripts)
  ├─ update .kb-toolkit-version       ← host
  └─ git commit                       ← host
```

**Key difference from Option B:** Explicitly define a "Docker contract" — Docker is invoked only for:
1. `claude` CLI (LLM operations)
2. `python3` (search engine)
3. Migration scripts (which may need tools inside the image)

Everything else runs on host.

**Additional design consideration — CLI version pinning:**

To address the divergence risk, the host CLI could embed a `MIN_IMAGE_VERSION` constant and the Docker image could embed a `MIN_CLI_VERSION`. On startup, cross-check both and warn/error on incompatibility.

**Pros:**
- All benefits of Option B
- **Clear separation of concerns** — Docker contract is explicit and narrow
- **Migration scripts remain in Docker** — they may need image-specific tools, keeping them in the image is correct
- **Version compatibility can be enforced** — bidirectional version check prevents silent breakage

**Cons:**
- Same host dependency requirements as Option B
- CLI is still larger than current thin wrapper
- Two update paths (same as Option B, but mitigated by version checks)

### Option D: No Docker — Direct Claude Code Installation

Eliminate Docker entirely. Users install Claude Code and Python directly on their host.

**Changes required:**
- `cli/kamosu`: Contains all logic, calls `claude` and `python3` directly
- Installation: `npm install -g @anthropic-ai/claude-code` + `pip install` for search dependencies
- `claude-base.md`: Distributed alongside CLI or fetched on first run

**Pros:**
- Simplest possible architecture — no Docker at all
- Zero container overhead
- Full access to host tools, git auth, filesystem
- Easiest for developers to debug and contribute

**Cons:**
- **Environment reproducibility lost** — different Node.js versions, Python versions, missing dependencies across machines
- **Installation complexity** — users must install Node.js, npm, Python, pip, and specific package versions
- **Lab deployment harder** — cannot guarantee consistent environment across research group members
- **`claude-base.md` distribution** — must be fetched/updated separately; no single artifact (Docker image) that bundles everything
- **Version management** — no clean way to pin "toolkit version" since there's no image; must rely on git tags or npm versioning
- **Conflicts with existing installations** — global npm/pip packages may conflict

---

## 3. Comparison Matrix

| Criterion | A (Docker + Git Auth) | B (Host-Centric) | C (Hybrid) | D (No Docker) |
|---|---|---|---|---|
| Git auth complexity | High (multi-platform) | None | None | None |
| Docker dependency | Required | Required (for claude) | Required (for claude) | None |
| Host dependencies | Docker only | Docker + bash/git | Docker + bash/git | Node.js, Python, git |
| Environment reproducibility | High | Medium | Medium | Low |
| CLI complexity | Low (~350 LOC) | High (~800-1000 LOC) | High (~800-1000 LOC) | Highest (~1200+ LOC) |
| Startup speed | Slow (full container) | Fast (Docker only for LLM) | Fast (Docker only for LLM) | Fastest |
| Tool availability | Limited to image | Host tools available | Host tools available | Full |
| Update mechanism | `docker pull` | CLI + `docker pull` | CLI + `docker pull` | CLI + npm/pip |
| Version coherence | High (single image) | Medium (cross-check) | Medium-High (cross-check) | Low |
| Windows support | Docker Desktop | WSL required | WSL required | Complex |
| Lab deployment ease | Easy (Docker) | Easy (Docker + curl) | Easy (Docker + curl) | Harder |

---

## 4. Recommendation

**Option C (Hybrid)** is recommended as the best balance of pragmatism and simplicity:

1. It **eliminates the Git auth problem entirely** — the #1 pain point that motivated this redesign
2. It **preserves Docker for what it's good at** — isolating LLM and Python dependencies
3. It **keeps lab deployment simple** — Docker + one `curl` install
4. It **has a clear, narrow Docker contract** — easy to document, test, and evolve
5. The **divergence risk is manageable** via bidirectional version checks

The migration from current architecture to Option C can be done incrementally:
1. First, move `git pull/push/commit` out of container scripts into `cli/kamosu`
2. Then, move file detection and queue writing to host
3. Finally, simplify container scripts to pure `claude` invocation wrappers

---

## 5. Detailed Design for Option C

### 5.1 Host CLI Structure

```bash
cli/kamosu
  ├── Helpers (die, require_docker, detect_compose_cmd, etc.)
  ├── Git helpers (git_pull_if_remote, git_commit_and_push)
  ├── Docker helpers (docker_claude, docker_search)
  │     docker_claude()  — runs: docker compose run --rm kb claude -p "..." --allowedTools "..."
  │     docker_search()  — runs: docker compose run --rm kb python3 /opt/kamosu/tools/...
  ├── cmd_compile()
  │     1. require_data_repo
  │     2. git_pull_if_remote          ← host
  │     3. detect_changed_files        ← host (bash find)
  │     4. write .ingest-queue         ← host
  │     5. docker_claude "compile prompt"  ← Docker
  │     6. touch .last-compile-timestamp   ← host
  │     7. rm .ingest-queue            ← host
  │     8. git_commit_and_push         ← host
  ├── cmd_lint()
  │     1. docker_claude "lint prompt" ← Docker
  │     2. git commit if --fix         ← host
  ├── cmd_promote()
  │     1. validate files              ← host
  │     2. docker_claude "promote prompt" ← Docker
  │     3. record .promote-history     ← host
  │     4. git_commit_and_push         ← host
  ├── cmd_search()
  │     1. docker_search               ← Docker
  ├── cmd_shell()
  │     1. docker compose run --rm kb claude "$@"  ← Docker
  ├── cmd_migrate()
  │     1. version check               ← host
  │     2. dirty check                 ← host
  │     3. docker run migrate scripts  ← Docker (if any)
  │     4. update .kb-toolkit-version  ← host
  │     5. git commit                  ← host
  └── cmd_init(), cmd_update(), cmd_version(), cmd_help()  (unchanged)
```

### 5.2 Docker Contract

The Docker image is invoked only for:

| Purpose | Command | Why Docker? |
|---------|---------|-------------|
| LLM compilation/lint/promote | `claude -p "..." --allowedTools "..."` | Claude Code CLI + Node.js dependency |
| LLM interactive session | `claude [args...]` | Claude Code CLI |
| Wiki search | `python3 searcher.py [args...]` | Python + TF-IDF libraries |
| Migration scripts | `bash /opt/kamosu/migrate/X.Y.Z.sh` | May need image-specific tools |

### 5.3 Version Compatibility

```bash
# In cli/kamosu:
KAMOSU_CLI_VERSION="0.2.0"
MIN_IMAGE_VERSION="0.2.0"

# In Docker image (checked via: docker run IMAGE cat /opt/kamosu/VERSION):
# /opt/kamosu/MIN_CLI_VERSION contains "0.2.0"

# On startup of any compose-based command:
check_version_compat() {
  local image_version=$(docker compose run --rm kb cat /opt/kamosu/VERSION)
  local min_cli=$(docker compose run --rm kb cat /opt/kamosu/MIN_CLI_VERSION 2>/dev/null || echo "0.0.0")
  # Warn if image_version < MIN_IMAGE_VERSION
  # Warn if KAMOSU_CLI_VERSION < min_cli
}
```

### 5.4 Migration Path

| Step | Change | Risk |
|------|--------|------|
| 1 | Move `git pull/push/commit` from container scripts to `cli/kamosu` | Low — git operations are straightforward bash |
| 2 | Move file detection (`detect_changed_files`) to `cli/kamosu` | Low — pure bash `find` |
| 3 | Move `.ingest-queue` / `.promote-history` / timestamp management to host | Low — file I/O only |
| 4 | Simplify container scripts to only contain `claude -p` invocations | Medium — must ensure prompts are correctly passed |
| 5 | Add version compatibility checks | Low |
| 6 | Update tests | Medium — test structure changes significantly |
| 7 | Update `kamosu-design.md` | Low |

---

## 6. Open Questions

1. **Should `claude-base.md` prompts be embedded in `cli/kamosu`?**
   Currently prompts reference `/opt/kamosu/claude-base.md` inside the container. If we keep this, Docker still needs the file. Alternatively, prompts could be constructed on the host and passed via stdin, but they reference the container-internal path for Claude Code to read.
   → Likely keep as-is: Claude Code reads `claude-base.md` from the container filesystem.

2. **Should `kamosu-search` move to host Python?**
   If users have Python 3 on their host, search could run natively. But this adds host dependency and version management complexity. Docker isolation is valuable here.
   → Likely keep search in Docker.

3. **How to handle the `--allowedTools` list?**
   Currently defined in container scripts. In Option C, the host CLI constructs the full `claude -p` invocation. The allowed tools list becomes part of the host CLI.
   → Move to host CLI. This is fine — allowed tools rarely change and are tied to the operation type, not the image version.

4. **Should we support running without Docker at all (for advanced users)?**
   If Claude Code is installed on the host, `kamosu compile` could detect it and skip Docker entirely.
   → Future enhancement. Not required for initial redesign.

---

## 7. Independent Review Feedback

Three independent reviewers evaluated this document from different perspectives: DevOps/Docker architecture, CLI UX/maintainability, and end-user adoption. All three endorsed **Option C (Hybrid)** as the right direction. Below is a consolidated summary of their feedback.

### 7.1 Consensus Points

All reviewers agreed on the following:

- **Option C is the right choice.** Git auth alone justifies the migration.
- **The version check in Section 5.3 is problematic.** Using `docker compose run` to read VERSION files spins up a full container (entrypoint, user creation, gosu) just to `cat` a file — twice. This is worse than the startup overhead Option C aims to fix.
- **Error handling after failed Claude invocations is under-specified.** The document doesn't address what happens when Docker/Claude fails mid-operation.

### 7.2 DevOps / Docker Architecture Review

**Key findings:**

1. **Version check must avoid container startup.** Replace `docker compose run ... cat VERSION` with Docker image labels (`LABEL kamosu.min_cli_version=0.2.0`) read via `docker inspect --format` — zero container startup cost.

2. **Prompt delivery mechanism is unresolved.** The document leaves "should prompts reference `/opt/kamosu/claude-base.md` inside the container?" as an open question. This needs an explicit design decision before implementation.

3. **`docker compose run --rm` per invocation is correct.** A long-running container with `docker exec` would add complexity (health checks, zombie cleanup, stale credentials) for marginal savings. Claude invocations are infrequent and long-running, so container startup is negligible relative to LLM execution time.

4. **File ownership gets simpler, not harder.** Git ops, `.ingest-queue`, timestamps all move to host (naturally owned by host user). Only Claude's wiki edits go through Docker, where the existing HOST_UID/GID + gosu mechanism works correctly.

5. **Bidirectional version check is over-engineered for v0.x.** A unidirectional check (CLI embeds `MIN_IMAGE_VERSION`) is sufficient for now. Add the reverse direction when actually needed.

6. **Existing semver comparison has a bug.** `entrypoint.sh` uses lexicographic `[[ "0.9.0" > "0.10.0" ]]` which gives the wrong answer. Use `sort -V` or a proper numeric comparison function.

7. **Security improves.** Moving git ops to host eliminates SSH key / agent socket mounting. The remaining exposure (`.env` with API keys visible in `docker inspect`) is unchanged but should be documented.

### 7.3 CLI UX / Maintainability Review

**Key findings:**

1. **~1000 LOC single bash file is fine.** Of the current 350 lines, ~130 are help text heredocs. After absorbing logic, real logic is ~400-500 lines + ~400-500 of help/boilerplate. This is well within single-file norms (nvm is 5000+ lines). Split only if it exceeds ~1200 LOC.

2. **`git_commit_and_push()` helper design.** Accept (a) commit message and (b) variadic paths to stage. Keep pre-commit guards (e.g., lint's `git diff --quiet` check) at the call site, not in the helper.

   ```bash
   git_commit_and_push() {
     local message="$1"; shift
     git add "$@"
     git commit -m "$message" || { warn "Nothing to commit."; return 0; }
     git_push_if_remote
   }
   ```

3. **Crash recovery for compile.** If Claude fails, `.ingest-queue` is left on disk but `.last-compile-timestamp` is NOT updated (it happens after Claude). This is actually a clean state — same files will be re-detected. Make this **intentional**: add a check at the top of `cmd_compile` for stale `.ingest-queue` and offer `--resume` / `--clean` options.

4. **Prompts should live in the Docker image, not the CLI.** Store compile/lint/promote prompts as files in `/opt/kamosu/prompts/`. Read them via `docker run --rm --entrypoint cat IMAGE /opt/kamosu/prompts/compile.txt`. This decouples prompt iteration from CLI distribution and avoids version divergence. Trade-off: one extra lightweight Docker invocation per command.

5. **Testing strategy should be three layers:**
   - **Unit tests** for pure bash functions (file detection, arg parsing, `is_promoted`) — no Docker mocks needed
   - **Integration tests** with mock `docker` binary — mock surface is now simpler (just `claude` invocations returning 0)
   - **Git tests** with `git init` in temp directories — test `git_pull_if_remote`, `git_commit_and_push`

   Testable surface area actually **improves** with Option C since most logic is plain bash.

### 7.4 End-User / Adoption Review

**Key findings:**

1. **Git auth is the #1 pain point.** "Being told kamosu cannot push because a Docker container lacks my credentials is infuriating — it feels like a tool fighting against my setup." Option C eliminates this entirely.

2. **WSL requirement is NOT a regression.** The current design (Option A) also effectively requires WSL for Docker Desktop on Windows. For Mac users with Docker Desktop, Options B/C are strictly better (no SSH socket forwarding issues). The document should state this explicitly.

3. **Option C genuinely reduces cognitive load.** The mental model "kamosu is a CLI that calls Docker only for the LLM" is simpler than "everything runs in Docker and I need to plumb my credentials through." The former matches how users think about other CLI tools.

4. **Error messages on version mismatch must be actionable.** `kamosu: CLI v0.2.0 requires image >= v0.2.0 (you have v0.1.0). Run: kamosu update` is acceptable. A generic "version mismatch" is not. Default to **warning**, not hard error, unless incompatibility causes data corruption.

5. **`--dry-run` should work without Docker.** Under Option C, the file-detection and queue-writing steps run on host, so `kamosu compile --dry-run` can show target files even when Docker is not running. This is a concrete UX improvement.

### 7.5 Action Items (Consolidated)

Based on all three reviews, the following changes should be incorporated into the Option C design before implementation:

| # | Action | Priority | Source |
|---|--------|----------|--------|
| 1 | Use Docker image labels + `docker inspect` for version checks instead of `docker compose run ... cat` | High | DevOps |
| 2 | Resolve prompt delivery: store prompts in Docker image at `/opt/kamosu/prompts/`, read via `docker run --entrypoint cat` | High | CLI UX |
| 3 | Add `.ingest-queue` stale file detection + `--resume`/`--clean` to `cmd_compile` | High | CLI UX |
| 4 | Check Claude/Docker exit code before proceeding to git commit | High | DevOps |
| 5 | Fix semver comparison to handle multi-digit segments (use `sort -V`) | Medium | DevOps |
| 6 | Drop bidirectional version check; use CLI-side `MIN_IMAGE_VERSION` only for v0.x | Medium | DevOps |
| 7 | Design `git_commit_and_push()` with variadic path args; keep guards at call sites | Medium | CLI UX |
| 8 | Plan three-layer test strategy (unit / integration / git) | Medium | CLI UX |
| 9 | Make version mismatch a warning (not hard error) with actionable message | Medium | End-user |
| 10 | Ensure `--dry-run` works without Docker running | Low | End-user |
| 11 | Add section markers (`# === SECTION ===`) when CLI grows; split at ~1200 LOC | Low | CLI UX |
| 12 | Explicitly note that WSL requirement is not a regression from current design | Low | End-user |
