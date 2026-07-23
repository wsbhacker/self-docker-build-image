# Brave Search MCP Server 自定义镜像构建 — 设计文档

- **日期**: 2026-07-22
- **状态**: 待评审
- **上游仓库**: https://github.com/brave/brave-search-mcp-server (TypeScript / Node.js 22+ / npm)
- **当前上游最新 tag**: `v2.1.0`

## 1. 目标

基于上游 `brave/brave-search-mcp-server` 仓库，构建并推送自己的 Docker 镜像到 ghcr.io：

- 构建时**输入 tag**，检出对应 tag 的上游源码版本再构建
- 构建脚本（工作流 + Dockerfile）由本仓库自己维护
- 与本仓库现有"从上游仓库构建"类镜像（open-web-search、trading-agents、glm-coding-grabber 等）的模式保持一致

## 2. 已确认需求

| 决策项 | 结论 | 理由 |
|--------|------|------|
| 构建执行位置 | GitHub Actions 工作流 | 仓库所有镜像的主路径；CLAUDE.md 注明不做本地测试 |
| Dockerfile 来源 | 本地维护上游副本 + 上游一致性检查 | 沿用 open-web-search 成熟模式 |
| Dockerfile 初版内容 | **直接完整复制上游最新 tag（v2.1.0）的 Dockerfile，不做任何改动** | 用户决定；简单、可与上游零差异 diff |
| 默认构建版本 | `v2.1.0`（当前上游最新 tag） | 用户决定 |
| 运行模式 | stdio 与 HTTP 均支持（参数化） | 由上游 exec-form ENTRYPOINT 天然支持，无需改 Dockerfile |
| 目标架构 | `linux/amd64` + `linux/arm64` | 纯 TS/Node 项目，无 native 依赖 |
| 镜像名称 | `ghcr.io/{owner}/brave-search` | 目录名 `brave-search/`，与官方镜像 `mcp/brave-search` 命名对齐 |
| 镜像 Tag | `type=raw,value=${{ inputs.version_tag }}`（如 `v2.1.0`） | 与 open-web-search 一致 |

## 3. 方案选型（已选 A）

| 方案 | 要点 | 结论 |
|------|------|------|
| **A. actions/checkout 检出上游源码 @ tag（选定）** | CI 以 `ref: <tag>` checkout 上游到 `./upstream-source`，本地 Dockerfile 构建 | ✅ 与仓库 12 个既有工作流模式一致；tag 有效性由官方 action 保证；可复用 drift check / gha 缓存 / 多架构模板 |
| B. Dockerfile 内 `ARG` + 容器内 `git clone --branch` | 单文件自包含 | ❌ 需镜像内装 git 走网络，慢且不稳；缓存利用差；偏离仓库模式 |
| C. CI curl 下载 tag tarball 解压构建 | 无二次 checkout | ❌ 解压目录名带 tag 后缀，路径处理多 edge case；与现有模式不一致 |
| D. re-tag 官方镜像 `mcp/brave-search` | 不构建只同步 | ❌ 不满足"自己的构建脚本/检出 tag 构建"需求；无法定制；依赖 Docker Hub |
| E. git submodule 钉住上游 | 版本锁定在 git 历史 | ❌ 与 workflow_dispatch 手动输入任意 tag 的核心需求冲突 |

## 4. 详细设计

### 4.1 目录与文件结构

```
self-docker-build-image/
├── brave-search/
│   └── Brave-search.Dockerfile          # 上游 v2.1.0 Dockerfile 的完整副本（逐字节一致）
├── .github/workflows/
│   └── build-brave-search.yml           # 新增工作流
└── CLAUDE.md                            # 更新镜像清单 + 工作流清单
```

> 命名遵循 CLAUDE.md 规范 `<name>/<Name>.Dockerfile`（与 anki/frp/litellm-pgvector 等 6 个目录一致；open-web-search 的裸 `Dockerfile` 为历史例外，不沿用）。

### 4.2 Dockerfile（`brave-search/Brave-search.Dockerfile`）

完整复制上游 v2.1.0 的 Dockerfile 原文，不做改动。其关键特征：

- 多阶段构建：`builder`（npm ci + tsc 构建）→ `release`（仅拷贝 `dist/`、`package*.json`，`npm ci --omit-dev`）
- 基础镜像 `node:alpine` 以 sha256 digest 钉死（可复现）
- `ENV NODE_ENV=production`、`ENV BRAVE_MCP_HOST=0.0.0.0`（容器内 HTTP 绑定所有网卡）
- 非 root：`USER node`
- `ENTRYPOINT ["node", "dist/index.js"]`，**无 CMD**

运行模式（均由 ENTRYPOINT 参数化，无需改镜像）：

```bash
# HTTP 服务模式（远程/多客户端）
docker run -d --name brave-search -p 8080:8080 \
  -e BRAVE_API_KEY=xxx \
  ghcr.io/{owner}/brave-search:v2.1.0 --transport http --port 8080

# stdio 模式（本地 MCP 客户端，如 Claude Code docker 挂载）
docker run --rm -i -e BRAVE_API_KEY=xxx \
  ghcr.io/{owner}/brave-search:v2.1.0
```

上游 CLI 参数（v2.1.0 已核实）：`--transport <stdio|http>`（默认 stdio）、`--port <number>`（默认 8080）、`--host <string>`（默认取 `BRAVE_MCP_HOST`）、`--brave-api-key`（默认取 `BRAVE_API_KEY` 环境变量）。

### 4.3 工作流（`.github/workflows/build-brave-search.yml`）

以 `build-open-web-search.yml` 为模板，差异点仅三处：上游仓库地址、paths 前缀、`platforms` 双架构。

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

### 4.4 错误处理与边界情况

| 场景 | 行为 |
|------|------|
| 输入的 tag 不存在 | `Checkout upstream source` 步骤失败，工作流红色终止，报错明确 |
| 上游该 tag 的 Dockerfile 与本地副本不一致 | 一致性检查步骤 `::error::` 终止；人工同步本地副本后重跑，或勾选 `force_build` 跳过 |
| arm64 构建 | 纯 TS/Node + `npm ci --ignore-scripts`（跳过 native 编译），QEMU 模拟无风险 |
| 上游钉死的 `node:alpine` digest / `openssl` 版本过期 | 由上游维护；若构建失败会在日志暴露，随一致性检查同步新版本解决 |
| 同 tag 重复构建 | ghcr 覆盖同 tag 镜像；gha 缓存命中，开销小，无害 |
| 目录变更自动触发（push） | `inputs.version_tag` 为空时回退默认 `v2.1.0`，行为与 open-web-search 一致 |

### 4.5 文档更新（CLAUDE.md）

- 镜像清单新增一行：`brave-search/` → `ghcr.io/{owner}/brave-search`，说明 "Brave Search MCP 服务器（从上游仓库构建）"
- 工作流文件清单新增：`.github/workflows/build-brave-search.yml - Brave Search MCP 服务器`

### 4.6 验证策略

遵循仓库约定**不做本地测试**：

1. CI 手动触发（workflow_dispatch，默认 `v2.1.0`）构建双架构镜像，工作流绿色 = 构建通过
2. 一致性检查步骤通过 = 本地 Dockerfile 与上游 v2.1.0 逐字节一致
3. 部署后用户自行验证：`docker run -d -p 8080:8080 -e BRAVE_API_KEY=xxx ghcr.io/{owner}/brave-search:v2.1.0 --transport http`，以 MCP 客户端（如 Claude Code）接入 `http://<host>:8080/mcp` 验证工具可用

## 5. 交付物清单

1. `brave-search/Brave-search.Dockerfile` — 上游 v2.1.0 Dockerfile 完整副本
2. `.github/workflows/build-brave-search.yml` — 构建工作流
3. `CLAUDE.md` — 更新镜像清单与工作流清单
