# Brave Search MCP 镜像构建 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `ghcr.io/{owner}/brave-search` 镜像构建能力：基于上游 `brave/brave-search-mcp-server` 指定 tag 的源码，通过 GitHub Actions 构建双架构镜像并推送 ghcr.io。

**Architecture:** 沿用仓库"从上游仓库构建"模式（与 open-web-search 同构）：CI 中 `actions/checkout` 检出上游源码 @ 输入 tag → 用本仓库维护的 Dockerfile 副本构建（构建前与上游同 tag Dockerfile diff 做一致性检查）→ buildx 双架构构建推送 ghcr.io。

**Tech Stack:** GitHub Actions (checkout@v6, docker/login-action@v3, setup-qemu-action@v4, setup-buildx-action@v4, metadata-action@v6, build-push-action@v7)、Docker Buildx 多架构、gha 缓存。

**Spec:** `docs/superpowers/specs/2026-07-22-brave-search-mcp-build-design.md`

## Global Constraints

- **不进行本地测试**（CLAUDE.md 强制规定）：本地不得执行 `docker build` / `docker run` 验证；验证仅限文件级检查（diff 上游、YAML 解析、grep）
- **Dockerfile 命名**：`<name>/<Name>.Dockerfile` → 本任务为 `brave-search/Brave-search.Dockerfile`
- **Dockerfile 内容**：与上游 v2.1.0 的 Dockerfile **逐字节一致**（curl 下载，diff 验证）
- **工作流 action 版本**（与仓库模板一致）：`actions/checkout@v6`、`docker/login-action@v3`、`docker/setup-qemu-action@v4`、`docker/setup-buildx-action@v4`、`docker/metadata-action@v6`、`docker/build-push-action@v7`
- **权限最小化**：仅 `contents: read` + `packages: write`
- **镜像名/Tag**：`ghcr.io/${{ github.repository_owner }}/brave-search`，tag 为 `type=raw,value=${{ inputs.version_tag || 'v2.1.0' }}`
- **默认 tag**：`v2.1.0`（当前上游最新 tag）
- **架构**：`linux/amd64,linux/arm64`
- **缓存**：`cache-from: type=gha` + `cache-to: type=gha,mode=max`
- **提交信息**：中文 conventional commit 风格，结尾附 `Co-Authored-By: Claude <noreply@anthropic.com>`

## File Structure

| 文件 | 动作 | 职责 |
|------|------|------|
| `brave-search/Brave-search.Dockerfile` | Create | 上游 v2.1.0 Dockerfile 逐字节副本（多阶段构建 node:alpine） |
| `.github/workflows/build-brave-search.yml` | Create | tag 输入 → 一致性检查 → 检出上游源码 → 双架构构建推送 ghcr |
| `CLAUDE.md` | Modify | 镜像清单 + 工作流清单各新增一行 |

---

### Task 1: 创建 brave-search/Brave-search.Dockerfile（上游 v2.1.0 副本）

**Files:**
- Create: `brave-search/Brave-search.Dockerfile`

**Interfaces:**
- Produces: 供 Task 2 工作流引用（`file: ./brave-search/Brave-search.Dockerfile`）及一致性检查 diff 的本地基线文件

- [ ] **Step 1: 创建目录并下载上游 v2.1.0 的 Dockerfile**

Run:
```bash
mkdir -p brave-search
curl -sfL https://raw.githubusercontent.com/brave/brave-search-mcp-server/v2.1.0/Dockerfile -o brave-search/Brave-search.Dockerfile
```

Expected: 命令静默成功（`-f` 使 HTTP 错误时非零退出）；`brave-search/Brave-search.Dockerfile` 存在。

> 用 curl 直接下载而非手写，保证与上游逐字节一致（含末尾换行等细节）。

- [ ] **Step 2: 验证与上游逐字节一致**

Run:
```bash
diff <(curl -sfL https://raw.githubusercontent.com/brave/brave-search-mcp-server/v2.1.0/Dockerfile) brave-search/Brave-search.Dockerfile && echo "BYTE-IDENTICAL"
```

Expected: 输出 `BYTE-IDENTICAL`，无任何 diff 差异输出。

- [ ] **Step 3: 健全性检查关键内容**

Run:
```bash
grep -n "AS builder" brave-search/Brave-search.Dockerfile
grep -n "AS release" brave-search/Brave-search.Dockerfile
grep -n 'ENTRYPOINT \["node", "dist/index.js"\]' brave-search/Brave-search.Dockerfile
grep -cn "CMD" brave-search/Brave-search.Dockerfile || true
```

Expected:
- 各有一条匹配：`FROM node:alpine@sha256:5209... AS builder`、`... AS release`、`ENTRYPOINT ["node", "dist/index.js"]`
- 最后一条输出 `0`（上游 Dockerfile 无 CMD —— stdio 默认、HTTP 靠运行时传参，这是设计预期）

- [ ] **Step 4: Commit**

```bash
git add brave-search/Brave-search.Dockerfile
git commit -m "feat(brave-search): 新增上游 v2.1.0 Dockerfile 副本

ghcr.io/{owner}/brave-search 镜像的构建定义，与上游
brave/brave-search-mcp-server v2.1.0 逐字节一致。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 创建构建工作流 build-brave-search.yml

**Files:**
- Create: `.github/workflows/build-brave-search.yml`

**Interfaces:**
- Consumes: Task 1 产出的 `brave-search/Brave-search.Dockerfile`（drift check 的 diff 基线 + build-push 的 `file:` 参数）
- Produces: 可手动触发（`version_tag` 输入）/ push 自动触发的构建流水线，产出 `ghcr.io/{owner}/brave-search:<tag>`

- [ ] **Step 1: 写入工作流文件**

创建 `.github/workflows/build-brave-search.yml`，内容如下（完整照抄，勿改动）：

```yaml
name: Build Brave Search MCP

on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "上游仓库 tag"
        default: "v2.1.0"
        required: false
      force_build:
        description: "跳过 Dockerfile 差异检查"
        type: boolean
        default: false
  push:
    branches: [main]
    paths:
      - "brave-search/**"
      - ".github/workflows/build-brave-search.yml"

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Check upstream Dockerfile changes
        if: ${{ !inputs.force_build }}
        run: |
          UPSTREAM_URL="https://raw.githubusercontent.com/brave/brave-search-mcp-server/${{ inputs.version_tag || 'v2.1.0' }}/Dockerfile"
          curl -sL "$UPSTREAM_URL" -o /tmp/upstream.Dockerfile
          if ! diff ./brave-search/Brave-search.Dockerfile /tmp/upstream.Dockerfile; then
            echo ""
            echo "::error::⚠️ 上游 Dockerfile 已变更，请检查并更新本地副本"
            exit 1
          fi
          echo "✅ Dockerfile 与上游一致"

      - name: Checkout upstream source
        uses: actions/checkout@v6
        with:
          repository: brave/brave-search-mcp-server
          ref: ${{ inputs.version_tag || 'v2.1.0' }}
          path: ./upstream-source

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
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
          images: ghcr.io/${{ github.repository_owner }}/brave-search
          tags: |
            type=raw,value=${{ inputs.version_tag || 'v2.1.0' }}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: ./upstream-source
          file: ./brave-search/Brave-search.Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: 验证 YAML 语法可解析**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-brave-search.yml')); print('YAML-OK')"
```

Expected: 输出 `YAML-OK`，无异常堆栈。

- [ ] **Step 3: 健全性检查关键字段**

Run:
```bash
grep -n "platforms: linux/amd64,linux/arm64" .github/workflows/build-brave-search.yml
grep -n "file: ./brave-search/Brave-search.Dockerfile" .github/workflows/build-brave-search.yml
grep -n "repository: brave/brave-search-mcp-server" .github/workflows/build-brave-search.yml
grep -n "default: \"v2.1.0\"" .github/workflows/build-brave-search.yml
grep -n "context: ./upstream-source" .github/workflows/build-brave-search.yml
```

Expected: 每条命令各输出 1 行匹配（双架构、Dockerfile 路径与 Task 1 文件名一致、上游仓库地址、默认 tag、构建上下文为上游源码目录）。

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-brave-search.yml
git commit -m "feat(brave-search): 新增构建工作流（tag 输入 + 一致性检查 + 双架构）

workflow_dispatch 输入 version_tag 检出上游对应 tag 源码构建；
构建前 diff 上游 Dockerfile（force_build 可跳过）；
amd64+arm64 构建推送 ghcr.io/{owner}/brave-search。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 更新 CLAUDE.md 镜像清单与工作流清单

**Files:**
- Modify: `CLAUDE.md`（镜像清单表格、工作流文件列表）

**Interfaces:**
- Consumes: Task 1 的目录 `brave-search/`、Task 2 的工作流文件 `.github/workflows/build-brave-search.yml`
- Produces: 文档与实际交付物一致（CLAUDE.md 要求新增镜像必须更新清单）

- [ ] **Step 1: 镜像清单表格新增一行**

在 `CLAUDE.md` 的「镜像清单」表格中，将：

```markdown
| `open-web-search/` | `ghcr.io/{owner}/open-web-search` | Open WebSearch MCP 服务器 (从上游仓库构建, 手动维护 Dockerfile) |
| `trading-agents/` | `ghcr.io/{owner}/trading-agents` | TradingAgents 多智能体交易分析框架 (从上游仓库构建, 常驻交互式 CLI) |
```

替换为：

```markdown
| `open-web-search/` | `ghcr.io/{owner}/open-web-search` | Open WebSearch MCP 服务器 (从上游仓库构建, 手动维护 Dockerfile) |
| `brave-search/` | `ghcr.io/{owner}/brave-search` | Brave Search MCP 服务器 (从上游仓库构建, 手动维护 Dockerfile) |
| `trading-agents/` | `ghcr.io/{owner}/trading-agents` | TradingAgents 多智能体交易分析框架 (从上游仓库构建, 常驻交互式 CLI) |
```

- [ ] **Step 2: 工作流文件清单新增一行**

在 `CLAUDE.md` 的「工作流文件」列表中，将：

```markdown
- `.github/workflows/build-open-web-search.yml` - Open WebSearch MCP 服务器
- `.github/workflows/build-trading-agents.yml` - TradingAgents 交易分析框架
```

替换为：

```markdown
- `.github/workflows/build-open-web-search.yml` - Open WebSearch MCP 服务器
- `.github/workflows/build-brave-search.yml` - Brave Search MCP 服务器
- `.github/workflows/build-trading-agents.yml` - TradingAgents 交易分析框架
```

- [ ] **Step 3: 验证两处新增均存在**

Run:
```bash
grep -n "brave-search/" CLAUDE.md
grep -n "build-brave-search.yml" CLAUDE.md
```

Expected: 第一条至少 1 行匹配（镜像清单表格行），第二条至少 1 行匹配（工作流清单行）。

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md 新增 brave-search 镜像与工作流清单

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 触发 CI 并验证产物（用户自行推送后参考执行）

**Files:** 无新增/修改（纯验证与交付）

**Interfaces:**
- Consumes: Task 1–3 的全部提交（当前分支 `brave-mcp`）
- Produces: ghcr.io 上可拉取的 `ghcr.io/{owner}/brave-search:v2.1.0` 双架构镜像

> ℹ️ 分支 push 与 merge 由用户自行完成，**不在本计划执行范围内**。本任务命令供用户推送/合入后参考。遵循仓库约定不做本地 docker 测试，以 CI 绿色为验收标准。

- [ ] **Step 1: 合入 main 后，手动触发构建（默认 v2.1.0）**

Run:
```bash
gh workflow run build-brave-search.yml -f version_tag=v2.1.0
sleep 5
gh run list --workflow=build-brave-search.yml --limit 1
```

Expected: 列出刚触发的 run，状态为 `queued`/`in_progress`。

- [ ] **Step 2: 等待工作流完成并确认绿色**

Run:
```bash
gh run watch --exit-status
```

Expected: 所有步骤成功，退出码 0（`Check upstream Dockerfile changes` 步骤输出 `✅ Dockerfile 与上游一致`）。

- [ ] **Step 3: 验证镜像已推送至 ghcr（双架构）**

Run:
```bash
OWNER=$(gh repo view --json owner --jq .owner.login)
gh api "/users/$OWNER/packages/container/brave-search/versions" --jq '.[].metadata.container.tags[]'
```

Expected: 输出包含 `v2.1.0`。如需验证双架构 manifest（本机有 docker 且已 ghcr 登录时，可选）：`docker manifest inspect ghcr.io/$OWNER/brave-search:v2.1.0 | grep -c '"architecture"'` 预期为 2（amd64 + arm64）。

- [ ] **Step 4: 告知用户部署验证方式（不在仓库内测试）**

向用户说明运行时验证命令（用户在自己的部署环境执行）：

```bash
# HTTP 模式
docker run -d --name brave-search -p 8080:8080 -e BRAVE_API_KEY=<key> \
  ghcr.io/<owner>/brave-search:v2.1.0 --transport http --port 8080
# MCP 端点: http://<host>:8080/mcp

# stdio 模式（本地 MCP 客户端）
docker run --rm -i -e BRAVE_API_KEY=<key> ghcr.io/<owner>/brave-search:v2.1.0
```
