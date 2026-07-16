# AKTools 镜像构建 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于 akfamily/aktools 源码 + 自定义 Dockerfile + requirements.txt，构建多架构 Docker 镜像推送到 ghcr.io。

**Architecture:** 单一 workflow（仅 workflow_dispatch），输入 aktools tag，从 requirements.txt 解析 akshare 版本。两次 checkout：self-docker-build-image（拿构建文件）+ akfamily/aktools（拿源码），通过 `pip install --no-deps` 防止 setup.py 覆盖已 pin 的依赖。

**Tech Stack:** Docker, GitHub Actions, Python 3.13-slim, docker/build-push-action@v7, docker/setup-qemu-action@v4

## Global Constraints

- 仅 `workflow_dispatch` 触发，无 push 自动触发
- 多架构 `linux/amd64,linux/arm64`
- 镜像 Tag 格式：`<aktools_version>-share-<akshare_version>`（aktools_version 去掉 `v` 前缀）
- akshare 版本从 `aktools/requirements.txt` 解析（单一数据源）
- 不进行本地测试（CLAUDE.md 规定）
- 权限最小化：`contents: read, packages: write`

---

### Task 1: Create `aktools/requirements.txt`

**Files:**
- Create: `aktools/requirements.txt`

**Interfaces:**
- Produces: 固定依赖列表（含 akshare 精确版本），被 Task 2 的 Dockerfile 和 Task 3 的 workflow 消费

- [ ] **Step 1: 创建 requirements.txt**

```text
akshare==1.16.25
fastapi==0.115.5
uvicorn==0.16.0
gunicorn==23.0.0
python-multipart==0.0.9
jinja2==3.1.2
typer[standard]==0.6.1
pydantic==1.10.2
alembic==1.8.1
SQLAlchemy==1.4.41
python-dotenv==0.21.0
```

> 依赖来源：合并上游 `setup.py` 的 `install_requires`（6项）+ 上游 `requirements.txt` 额外依赖（4项）+ 上游 Dockerfile 中的 `gunicorn`。版本 pin 住以确保可复现构建。

- [ ] **Step 2: 提交**

```bash
git add aktools/requirements.txt
git commit -m "feat: add aktools requirements.txt with pinned dependencies

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create `aktools/Aktools.Dockerfile`

**Files:**
- Create: `aktools/Aktools.Dockerfile`

**Interfaces:**
- Consumes: `aktools/requirements.txt`（Task 1）
- Produces: Docker 镜像（通过 `docker build`），被 Task 3 的 workflow 调用

- [ ] **Step 1: 创建 Dockerfile**

```dockerfile
FROM python:3.13-slim-bullseye

RUN pip install --upgrade pip

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY aktools-src /aktools-src
RUN pip install --no-cache-dir --no-deps /aktools-src

WORKDIR /usr/local/lib/python3.13/site-packages/aktools
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app", "-k", "uvicorn.workers.UvicornWorker"]
```

> `--no-deps` 防止 `setup.py` 的 `install_requires`（`akshare>=1.16.25` 等）覆盖 requirements.txt 中 pin 的精确版本。`COPY . /aktools-src` 复制的是 workflow 中 checkout 到 `aktools/aktools-src/` 的 aktools 源码。

- [ ] **Step 2: 提交**

```bash
git add aktools/Aktools.Dockerfile
git commit -m "feat: add aktools Dockerfile with custom dependency management

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Create `.github/workflows/build-aktools.yml`

**Files:**
- Create: `.github/workflows/build-aktools.yml`

**Interfaces:**
- Consumes: `aktools/Aktools.Dockerfile`（Task 2），`aktools/requirements.txt`（Task 1）
- Produces: 构建并推送镜像到 `ghcr.io/{owner}/aktools:<version>-share-<akshare_version>`

- [ ] **Step 1: 创建 workflow 文件**

```yaml
name: Build aktools Image

on:
  workflow_dispatch:
    inputs:
      aktools_version:
        description: "AKTools 上游 Tag（如 v0.0.91 或 0.0.91）"
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
      - name: Checkout self-docker-build-image（获取构建文件）
        uses: actions/checkout@v6

      - name: Checkout akfamily/aktools 源码
        uses: actions/checkout@v6
        with:
          repository: akfamily/aktools
          ref: ${{ inputs.aktools_version }}
          path: aktools/aktools-src

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

      - name: Parse versions and construct tag
        id: versions
        run: |
          AKTOOLS_VER=$(echo "${{ inputs.aktools_version }}" | sed 's/^v//')
          AKSHARE_VER=$(grep -oP 'akshare==\K[^\s]+' aktools/requirements.txt)
          TAG="${AKTOOLS_VER}-share-${AKSHARE_VER}"
          echo "aktools_version=${AKTOOLS_VER}" >> $GITHUB_OUTPUT
          echo "akshare_version=${AKSHARE_VER}" >> $GITHUB_OUTPUT
          echo "tag=${TAG}" >> $GITHUB_OUTPUT
          echo "Resolved tag: $TAG"

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: ./aktools
          file: ./aktools/Aktools.Dockerfile
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.versions.outputs.tag }}
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

> **关键设计点：**
> - 两次 checkout：先拉自己的仓库（拿 Dockerfile + requirements.txt），再拉 aktools 源码到 `aktools/aktools-src/`
> - `sed 's/^v//'` 处理输入 tag 带 `v` 前缀的情况（如 `v0.0.91` → `0.0.91`）
> - `grep -oP` 从 requirements.txt 解析 akshare 精确版本
> - 构建上下文为 `aktools/`，Dockerfile 中的 `COPY aktools-src /aktools-src` 复制的是 checkout 到 `aktools/aktools-src/` 的源码
> - 使用 GHA 缓存加速构建
> - `push: true` + `docker/login-action` 前置，一步完成构建和推送

- [ ] **Step 2: 提交**

```bash
git add .github/workflows/build-aktools.yml
git commit -m "feat: add aktools build workflow with multi-arch support

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Update project documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: 所有前序 Tasks 的文件路径和镜像信息
- Produces: 更新后的项目文档和 gitignore

- [ ] **Step 1: 在 CLAUDE.md 镜像清单中添加 aktools 条目**

在 `| \`anki/\` | ...` 行之后插入：

```markdown
| `aktools/` | `ghcr.io/{owner}/aktools` | AKTools HTTP API 服务（从上游源码构建，自定义依赖管理） |
```

- [ ] **Step 2: 在 .gitignore 中添加 aktools-src 排除规则**

```diff
 .claude/settings.local.json
+aktools/aktools-src/
```

> 防止在本地手动 checkout aktools 源码后误提交到本仓库。

- [ ] **Step 3: 提交**

```bash
git add CLAUDE.md .gitignore
git commit -m "docs: add aktools to image catalog and gitignore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Final verification

**Files:**
- （无新建/修改文件）

- [ ] **Step 1: 检查所有文件存在且内容正确**

```bash
echo "=== File listing ==="
ls -la aktools/Aktools.Dockerfile aktools/requirements.txt .github/workflows/build-aktools.yml
echo ""
echo "=== Dockerfile ==="
cat aktools/Aktools.Dockerfile
echo ""
echo "=== requirements.txt ==="
cat aktools/requirements.txt
echo ""
echo "=== Workflow trigger ==="
head -5 .github/workflows/build-aktools.yml
```

- [ ] **Step 2: 验证 requirements.txt 中 akshare 版本解析**

```bash
grep -oP 'akshare==\K[^\s]+' aktools/requirements.txt && echo "Parse OK" || echo "Parse FAILED"
```

- [ ] **Step 3: 验证 git 状态干净**

```bash
git status
```

预期：所有文件已提交，working tree clean。

- [ ] **Step 4: 最终提交（如有遗漏）**

```bash
git add -A && git diff --cached --stat
# 如果有待提交内容：
git commit -m "chore: final verification adjustments

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 文件结构总结

```
aktools/
├── Aktools.Dockerfile    ← Task 2: 自定义 Dockerfile
├── requirements.txt      ← Task 1: 固定依赖（pin 精确版本）
└── aktools-src/          ← CI 运行时 checkout（不提交到仓库）

.github/workflows/
└── build-aktools.yml     ← Task 3: 手动构建 workflow
```

## 构建流程回顾

```
用户触发 workflow_dispatch
  输入: aktools_version = v0.0.91
    ↓
checkout self-docker-build-image → 拿构建文件
checkout akfamily/aktools @ v0.0.91 → aktools/aktools-src/
    ↓
解析 requirements.txt → akshare==1.16.25
剥掉 v 前缀 → aktools_version = 0.0.91
    ↓
docker build + push
  镜像: ghcr.io/{owner}/aktools:0.0.91-share-1.16.25
  平台: linux/amd64,linux/arm64
```
