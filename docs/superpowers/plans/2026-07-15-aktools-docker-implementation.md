# AKTools Docker 镜像包装与升级 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建两个 GitHub Actions 工作流：一个包装上游 aktools 镜像到 ghcr.io，另一个基于自有镜像升级 AKShare 版本。

**Architecture:** Workflow 1 使用 Docker CLI 直接从阿里云 registry 拉取上游镜像并重打 tag 后推送到 ghcr.io（无需 Dockerfile）。Workflow 2 使用标准 docker/build-push-action，通过 Dockerfile `FROM` 我们自己的 ghcr.io 镜像并 pip install 升级 akshare。

**Tech Stack:** GitHub Actions, Docker CLI, docker/build-push-action@v7, docker/metadata-action@v6

## Global Constraints

- 不进行本地测试（CLAUDE.md）
- 单一架构（从上游透传，无 multi-arch）
- 无需新增 Secret，仅用 GITHUB_TOKEN
- 遵循项目现有工作流命名和结构惯例

## File Structure

| 文件 | 操作 | 职责 |
|------|------|------|
| `aktools/aktools-upgrade.Dockerfile` | 创建 | Workflow 2 的升级 Dockerfile — FROM 自有镜像 + pip install akshare |
| `.github/workflows/build-aktools.yml` | 创建 | Workflow 1 — pull from aliyun → retag → push to ghcr.io |
| `.github/workflows/build-aktools-upgrade.yml` | 创建 | Workflow 2 — docker build with build-args → push to ghcr.io |
| `CLAUDE.md` | 修改 | 添加 aktools 到镜像清单 |

---

### Task 1: 创建 aktools 目录和升级 Dockerfile

**Files:**
- Create: `aktools/aktools-upgrade.Dockerfile`

**Interfaces:**
- Consumes: 无（这是第一个交付物）
- Produces: `aktools-upgrade.Dockerfile` — 接受 `BASE_VERSION` 和 `AKSHARE_VERSION` 两个 ARG，FROM `ghcr.io/0xW5B/aktools:${BASE_VERSION}`，RUN `pip install akshare==${AKSHARE_VERSION}`

- [ ] **Step 1: 创建 aktools 目录**

```bash
mkdir -p aktools
```

- [ ] **Step 2: 编写 aktools-upgrade.Dockerfile**

```dockerfile
ARG BASE_VERSION=1.8.95
FROM ghcr.io/0xW5B/aktools:${BASE_VERSION}

ARG AKSHARE_VERSION
RUN pip install akshare==${AKSHARE_VERSION} -i https://pypi.org/simple
```

- [ ] **Step 3: 提交**

```bash
git add aktools/
git commit -m "feat: add aktools-upgrade Dockerfile for akshare version bump"
```

---

### Task 2: 创建 Workflow 1 — 包装上游 aktools

**Files:**
- Create: `.github/workflows/build-aktools.yml`

**Interfaces:**
- Consumes: 无
- Produces: `build-aktools.yml` — 手动或 push 触发时，从阿里云 registry pull 上游镜像，retag 后推送到 ghcr.io

- [ ] **Step 1: 编写 build-aktools.yml**

```yaml
name: Build aktools Image (from upstream)

on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "上游 aktools 版本号 (例如: 1.8.95)"
        required: false
        default: "latest"
        type: string

  push:
    branches:
      - main
    paths:
      - "aktools/**"
      - ".github/workflows/build-aktools.yml"

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/aktools
  UPSTREAM_REGISTRY: registry.cn-shanghai.aliyuncs.com
  UPSTREAM_IMAGE: akfamily/aktools

jobs:
  mirror-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set version tag
        id: tag
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "value=${{ inputs.version_tag }}" >> $GITHUB_OUTPUT
          else
            echo "value=latest" >> $GITHUB_OUTPUT
          fi

      - name: Pull, retag, and push
        run: |
          UPSTREAM_REF="${{ env.UPSTREAM_REGISTRY }}/${{ env.UPSTREAM_IMAGE }}:${{ steps.tag.outputs.value }}"
          GHCR_REF="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.tag.outputs.value }}"

          echo "Pulling $UPSTREAM_REF ..."
          docker pull "$UPSTREAM_REF"

          echo "Tagging as $GHCR_REF ..."
          docker tag "$UPSTREAM_REF" "$GHCR_REF"

          echo "Pushing $GHCR_REF ..."
          docker push "$GHCR_REF"

          echo "Done: $GHCR_REF"
```

- [ ] **Step 2: 提交**

```bash
git add .github/workflows/build-aktools.yml
git commit -m "feat: add aktools mirror workflow - pull from aliyun, push to ghcr"
```

---

### Task 3: 创建 Workflow 2 — 升级 AKShare

**Files:**
- Create: `.github/workflows/build-aktools-upgrade.yml`

**Interfaces:**
- Consumes: `aktools/aktools-upgrade.Dockerfile` (from Task 1), `ghcr.io/0xW5B/aktools:<base_version>` (from Task 2 workflow execution)
- Produces: `build-aktools-upgrade.yml` — 手动触发时基于指定基础版本构建升级后的镜像

- [ ] **Step 1: 编写 build-aktools-upgrade.yml**

```yaml
name: Build aktools Image (AKShare upgraded)

on:
  workflow_dispatch:
    inputs:
      base_version:
        description: "基础 aktools 版本 (例如: 1.8.95)"
        required: true
        default: "1.8.95"
        type: string
      akshare_version:
        description: "目标 AKShare 版本 (例如: 1.14.90)"
        required: true
        type: string

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/aktools

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=${{ inputs.base_version }}-akshare-${{ inputs.akshare_version }}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: ./aktools
          file: ./aktools/aktools-upgrade.Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          build-args: |
            BASE_VERSION=${{ inputs.base_version }}
            AKSHARE_VERSION=${{ inputs.akshare_version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: 提交**

```bash
git add .github/workflows/build-aktools-upgrade.yml
git commit -m "feat: add aktools akshare upgrade workflow with versioned tags"
```

---

### Task 4: 更新 CLAUDE.md 镜像清单

**Files:**
- Modify: `CLAUDE.md:8-20`（镜像清单表格）

**Interfaces:**
- Consumes: 所有前述交付物
- Produces: 更新后的 CLAUDE.md，新镜像在清单中有文档记录

- [ ] **Step 1: 在镜像清单表格末尾添加 aktools 行**

在 `CLAUDE.md` 的镜像清单表格中，在 `pg-ocs-sync-worker/` 行之后添加：

```markdown
| `aktools/` | `ghcr.io/{owner}/aktools` | AKTools 金融数据 API 服务 — 包装上游 aktools 镜像 (从阿里云), 支持独立 AKShare 版本升级 |
```

- [ ] **Step 2: 提交**

```bash
git add CLAUDE.md
git commit -m "docs: add aktools to image catalog in CLAUDE.md"
```

---

## 执行顺序

Task 1 → Task 2 → Task 3 → Task 4

Tasks 1-2 可以并行（无依赖），但 Task 3 语义上依赖 Task 2 产出的基础镜像（首次运行时需先执行一次 Workflow 1）。Task 4 应最后执行以汇总所有变更。
