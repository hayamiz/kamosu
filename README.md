# kamosu — LLM-Powered Knowledge Base Toolkit

kamosu (醸す, "to brew/cultivate") is a Docker-based toolkit that uses LLMs to build and maintain research knowledge bases. Raw data (papers, web articles, code snippets, etc.) is "compiled" by Claude Code into a Markdown wiki, browsable in Obsidian.

## Features

- **LLM as data compiler** — Wiki articles are generated and maintained by the LLM. You just feed in raw data.
- **Separation of tools and data** — The toolkit is distributed as a Docker image; your data lives in its own Git repository.
- **Obsidian-native** — `[[wikilink]]` syntax, YAML frontmatter, graph view and backlinks work out of the box.
- **Progressive scaling** — Flat index for small KBs, hierarchical index + search tools as it grows.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hayamiz/kamosu/master/cli/kamosu | \
  sudo install /dev/stdin /usr/local/bin/kamosu
```

Requires: Docker

## Quick Start

### 1. Initialize a knowledge base

```bash
kamosu init my-research-topic
```

This creates a `my-research-topic/` directory with all scaffolding and authentication config.

### 2. Setup

```bash
cd my-research-topic

# Edit CLAUDE.md for your research domain
vim CLAUDE.md

# Git init
git init
git remote add origin <your-remote-url>
git add -A && git commit -m "init: knowledge base"
git push -u origin main
```

### 3. Ingest data and compile

```bash
# Add raw data
cp ~/Downloads/paper.pdf raw/papers/

# Compile (Claude Code generates wiki articles)
kamosu compile
```

### 4. Browse

Open `my-research-topic/` as an Obsidian Vault. Articles in `wiki/` are viewable with graph view and backlinks.

## Commands

| Command | Description |
|---------|-------------|
| `kamosu init <kb-name>` | Initialize a new knowledge base |
| `kamosu compile [options]` | Compile raw data into wiki articles |
| `kamosu lint [options]` | Run wiki health checks |
| `kamosu search <query>` | Search the wiki |
| `kamosu shell [args...]` | Open an interactive Claude Code session |
| `kamosu migrate [options]` | Run data repository migrations |
| `kamosu update` | Pull the latest Docker image |
| `kamosu version` | Show version information |
| `kamosu help` | Show usage help |

### kamosu init

```bash
kamosu init [OPTIONS] <kb-name>
```

| Option | Description |
|--------|-------------|
| `--claude-oauth` | Claude OAuth mode (mount host credentials) |
| `--claude-bedrock` | AWS Bedrock mode |
| `--aws-profile <name>` | AWS profile name (with `--claude-bedrock`) |
| `--aws-region <region>` | AWS region (required with `--claude-bedrock`) |

Without auth options, an interactive prompt is shown.

### kamosu compile

```bash
kamosu compile [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--force` | Recompile all raw files |
| `--dry-run` | Show target files only (no compilation) |
| `--file <path>` | Compile a specific file |

### kamosu lint

```bash
kamosu lint [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--fix` | Auto-fix issues where possible |
| `--check-only` | Report only (default) |

## Authentication

kamosu supports 3 authentication modes, selected during `kamosu init`:

### Claude OAuth (default)

Mounts the host machine's Claude Code credentials into the container.

**Prerequisite**: Run `claude` on the host once to complete OAuth.

```bash
kamosu init --claude-oauth my-topic
```

### AWS Bedrock (profile)

```bash
kamosu init --claude-bedrock --aws-profile your-profile --aws-region us-east-1 my-topic
```

### AWS Bedrock (EC2 IAM Role)

```bash
kamosu init --claude-bedrock --aws-region us-east-1 my-topic
```

### Reconfigure authentication

```bash
kamosu shell -- kamosu-init --reconfigure
```

Existing `.kamosu-config` is backed up before overwriting.

## Data Repository Structure

```
my-topic/
├── CLAUDE.md                 # KB-specific LLM instructions (user-editable)
├── docker-compose.yml
├── docker-compose.claude-auth.yml  # OAuth auth override
├── .kamosu-config / .kamosu-config.example
├── .gitignore
├── .kamosu-version
├── raw/                      # Raw data (user-managed)
│   ├── papers/
│   ├── web-clips/
│   └── repos/
├── wiki/                     # LLM-generated articles (do not edit manually)
│   ├── _master_index.md
│   ├── _category/
│   ├── _cross_references.md
│   ├── concepts/
│   └── my-drafts/            # User drafts (LLM reads but does not edit)
└── outputs/                  # Q&A results, reports, etc.
```

## Development

For local development without the published Docker image:

### Build locally

```bash
cd kamosu/
docker build -t kamosu:local .
```

### Test with local image

```bash
# Override the image in .kamosu-config
echo 'KB_TOOLKIT_VERSION=local' >> .kamosu-config

# Or edit docker-compose.yml directly:
# image: kamosu:local
```

### Run tests

```bash
make test
```

## License

TBD
