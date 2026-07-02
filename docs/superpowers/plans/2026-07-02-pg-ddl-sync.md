# pg-ddl-sync Docker 镜像构建 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 PostgreSQL DDL 同步伴生服务添加 GitHub Actions 自动构建工作流，镜像推送至 `ghcr.io/{owner}/pg-ddl-sync`

**Architecture:** 纯 Python 3.11 Alpine 容器，安装 `psycopg2-binary` 后直接运行 `ddl_worker.py`。工作流遵循项目标准模式（checkout → login → QEMU → Buildx → metadata → build-push），支持多架构 + GHA 缓存。

**Tech Stack:** Python 3.11 Alpine, psycopg2-binary 2.9.9, GitHub Actions, Docker Buildx

## Global Constraints

- 不进行本地测试（参见 CLAUDE.md）
- Dockerfile 使用非 root 用户运行
- Dockerfile 包含 HEALTHCHECK
- `psycopg2-binary==2.9.9` 对 Alpine amd64/arm64 有预编译 wheel，不添加编译依赖
- 权限最小化：`contents:read, packages:write`

---

### Task 1: 重命名并改进 Dockerfile

**Files:**
- Delete: `pg-ocs-sync-worker/Dockerfile`
- Create: `pg-ocs-sync-worker/PgDdlSync.Dockerfile`

**Interfaces:**
- Produces: `PgDdlSync.Dockerfile` — 被 Task 2 的工作流引用 (`file: ./pg-ocs-sync-worker/PgDdlSync.Dockerfile`)

- [ ] **Step 1: 删除旧 Dockerfile**

```bash
rm pg-ocs-sync-worker/Dockerfile
```

- [ ] **Step 2: 创建改进后的 Dockerfile**

写入 `pg-ocs-sync-worker/PgDdlSync.Dockerfile`：

```dockerfile
FROM python:3.11-alpine
WORKDIR /app

# 创建非 root 用户
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ddl_worker.py .

# 健康检查：每 30s 检查进程是否存在
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep -f ddl_worker.py || exit 1

USER appuser
CMD ["python", "-u", "ddl_worker.py"]
```

- [ ] **Step 3: 验证目录结构**

```bash
ls -la pg-ocs-sync-worker/
```

Expected: 只有 `PgDdlSync.Dockerfile`、`requirements.txt`、`ddl_worker.py`（无 `Dockerfile`）

- [ ] **Step 4: Commit**

```bash
git add pg-ocs-sync-worker/Dockerfile pg-ocs-sync-worker/PgDdlSync.Dockerfile
git commit -m "refactor: rename and improve pg-ddl-sync Dockerfile

- Add non-root user (appuser)
- Add HEALTHCHECK via pgrep
- Rename to PgDdlSync.Dockerfile per project convention"
```

---

### Task 2: 创建 GitHub Actions 工作流

**Files:**
- Create: `.github/workflows/build-pg-ddl-sync.yml`

**Interfaces:**
- Consumes: `pg-ocs-sync-worker/PgDdlSync.Dockerfile`（Task 1 产出）
- Consumes: `pg-ocs-sync-worker/ddl_worker.py`, `pg-ocs-sync-worker/requirements.txt`（已有文件）

- [ ] **Step 1: 创建工作流文件**

写入 `.github/workflows/build-pg-ddl-sync.yml`：

```yaml
name: Build pg-ddl-sync Image

on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "设定镜像 Tag (例如: v1.0.0 或 latest)"
        required: false
        default: "latest"
        type: string

  push:
    branches:
      - main
    paths:
      - "pg-ocs-sync-worker/**"
      - ".github/workflows/build-pg-ddl-sync.yml"

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/pg-ddl-sync

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
        uses: docker/login-action@v3
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
          context: ./pg-ocs-sync-worker
          file: ./pg-ocs-sync-worker/PgDdlSync.Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: 验证 YAML 语法**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-pg-ddl-sync.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-pg-ddl-sync.yml
git commit -m "ci: add pg-ddl-sync Docker image build workflow

- Multi-arch: linux/amd64, linux/arm64
- Triggers: workflow_dispatch + push on pg-ocs-sync-worker/** changes
- Image: ghcr.io/{owner}/pg-ddl-sync"
```

---

### Task 3: 更新 CLAUDE.md 镜像清单

**Files:**
- Modify: `CLAUDE.md:10`（在 `anki/` 行之前插入新行）

**Interfaces:**
- Consumes: 无（独立任务）

- [ ] **Step 1: 在镜像清单表格末尾新增一行**

在 `CLAUDE.md` 中，在 `trading-agents/` 行之后插入：

```markdown
| `pg-ocs-sync-worker/` | `ghcr.io/{owner}/pg-ddl-sync` | PostgreSQL DDL 同步伴生服务 (Python) |
```

使用 Edit 工具，在 `trading-agents/` 的表格行后插入新行。

- [ ] **Step 2: 在工作流文件清单中新增一行**

在 `CLAUDE.md` 的工作流文件列表中，在 `build-trading-agents.yml` 行之后插入：

```markdown
- `.github/workflows/build-pg-ddl-sync.yml` - PostgreSQL DDL 同步伴生服务
```

- [ ] **Step 3: 验证 CLAUDE.md 格式**

```bash
head -35 CLAUDE.md
```

确认镜像清单和工作流列表中新条目格式正确。

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add pg-ddl-sync to image inventory and workflow list"
```

---

## Execution Order

```
Task 1 (Dockerfile) ──┐
                      ├──> Task 2 (Workflow) ──> Task 3 (CLAUDE.md)
                      │
                      └──> Task 3 is independent, can run in parallel with Task 1
```

**推荐顺序**：Task 1 → Task 2 → Task 3（因为 Task 2 引用 Task 1 的 Dockerfile 名称，Task 3 引用 Task 2 的工作流文件名）
