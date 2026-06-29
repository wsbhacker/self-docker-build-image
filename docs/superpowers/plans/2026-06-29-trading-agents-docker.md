# TradingAgents Docker Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ghcr.io/{owner}/trading-agents` image to the build pipeline, packaging the TauricResearch/TradingAgents interactive CLI in a long-running container.

**Architecture:** Python 3.12-slim base, git clone from upstream at a specified tag/branch, pip install, sleep infinity to keep container alive for `docker exec -it <name> tradingagents` access.

**Tech Stack:** Docker, GitHub Actions, Python 3.12

**Design doc:** `docs/superpowers/specs/2026-06-29-trading-agents-docker-design.md`

## Global Constraints

- 不进行本地测试
- 多架构: linux/amd64, linux/arm64
- 权限: contents:read, packages:write
- GHA cache: type=gha, mode=max
- Version tag via workflow_dispatch `version_tag` input, default "latest"
- Upstream git ref via workflow_dispatch `upstream_version` input, default "main"

---

### Task 1: Create Dockerfile

**Files:**
- Create: `trading-agents/TradingAgents.Dockerfile`

**Interfaces:**
- Produces: Docker image with build arg `TRADINGAGENTS_VERSION` (default: `main`), user `appuser`, workdir `/home/appuser`, entrypoint `sleep infinity`

- [ ] **Step 1: Create the Dockerfile**

```dockerfile
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG TRADINGAGENTS_VERSION=main

WORKDIR /app
RUN git clone --depth 1 --branch ${TRADINGAGENTS_VERSION} \
    https://github.com/TauricResearch/TradingAgents.git . \
    && pip install --no-cache-dir . \
    && rm -rf .git

RUN useradd -m appuser \
    && mkdir -p /home/appuser/.tradingagents \
    && chown -R appuser:appuser /home/appuser
USER appuser
WORKDIR /home/appuser

ENTRYPOINT ["sleep", "infinity"]
```

- [ ] **Step 2: Commit**

```bash
git add trading-agents/TradingAgents.Dockerfile
git commit -m "feat: add TradingAgents Dockerfile with git tag support

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create CI/CD workflow

**Files:**
- Create: `.github/workflows/build-trading-agents.yml`

**Interfaces:**
- Consumes: `trading-agents/TradingAgents.Dockerfile` from Task 1

- [ ] **Step 1: Create the workflow file**

```yaml
name: Build trading-agents Image

on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "设定镜像 Tag (如 latest)"
        required: false
        default: "latest"
        type: string
      upstream_version:
        description: "上游 Git ref (如 v0.3.0 或 main)"
        required: false
        default: "main"
        type: string

  push:
    branches:
      - main
    paths:
      - "trading-agents/**"
      - ".github/workflows/build-trading-agents.yml"

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/trading-agents

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Log in to the Container registry
        uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=${{ inputs.version_tag }},enable=${{ github.event_name == 'workflow_dispatch' }}
            type=raw,value=latest,enable=${{ github.event_name == 'push' }}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: ./trading-agents
          file: ./trading-agents/TradingAgents.Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          build-args: TRADINGAGENTS_VERSION=${{ inputs.upstream_version || 'main' }}
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build-trading-agents.yml
git commit -m "feat: add TradingAgents CI/CD workflow

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Update CLAUDE.md image manifest

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: image name `ghcr.io/{owner}/trading-agents` from spec, directory name `trading-agents/` from Task 1, workflow filename from Task 2

- [ ] **Step 1: Add image to the manifest table**

In `CLAUDE.md`, find the image manifest table. After the `open-web-search/` row, add a new row:

```markdown
| `trading-agents/` | `ghcr.io/{owner}/trading-agents` | TradingAgents 多智能体交易框架 (从上游仓库构建, 交互式 CLI) |
```

Actual edit target — the table currently ends with:

```markdown
| `open-web-search/` | `ghcr.io/{owner}/open-web-search` | Open WebSearch MCP 服务器 (从上游仓库构建, 手动维护 Dockerfile) |
```

Insert after this line:

```markdown
| `trading-agents/` | `ghcr.io/{owner}/trading-agents` | TradingAgents 多智能体交易分析框架 (从上游仓库构建, 常驻交互式 CLI) |
```

- [ ] **Step 2: Add workflow file to the workflow list**

In `CLAUDE.md`, find the workflow file list. After the `build-open-web-search.yml` line, add:

```markdown
- `.github/workflows/build-trading-agents.yml` - TradingAgents 交易分析框架
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add TradingAgents to image manifest and workflow list

Co-Authored-By: Claude <noreply@anthropic.com>"
```
