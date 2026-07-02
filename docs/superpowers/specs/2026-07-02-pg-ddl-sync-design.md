# pg-ddl-sync Docker 镜像构建设计

## 概述

为 `pg-ocs-sync-worker/` 目录下的 PostgreSQL DDL 同步伴生服务添加 GitHub Actions 自动构建工作流，将镜像推送到 `ghcr.io/{owner}/pg-ddl-sync`。

## 背景

`ddl_worker.py` 是一个 PostgreSQL DDL 同步伴生服务，功能：
- 连接主库和从库 PostgreSQL 数据库
- 从主库 `ddl_log` 表读取未同步的 DDL 变更
- 在从库重放 DDL 并刷新逻辑复制订阅 (`ALTER SUBSCRIPTION ... REFRESH PUBLICATION`)
- 通过 `LISTEN/NOTIFY` 机制实时监听主库 DDL 变动

## 文件变更

| 操作 | 文件 | 说明 |
|------|------|------|
| 重命名+改进 | `pg-ocs-sync-worker/Dockerfile` → `PgDdlSync.Dockerfile` | 添加非 root 用户 + HEALTHCHECK |
| 新建 | `.github/workflows/build-pg-ddl-sync.yml` | CI/CD 构建推送工作流 |
| 修改 | `CLAUDE.md` | 镜像清单新增条目 |

## Dockerfile 改进

### 改进前

```dockerfile
FROM python:3.11-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY ddl_worker.py .
CMD ["python", "-u", "ddl_worker.py"]
```

### 改进后

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

**变更点：**
- **非 root 用户**：创建 `appuser` / `appgroup`，以最小权限运行
- **HEALTHCHECK**：`pgrep` 检测进程存活，容器编排系统可感知健康状态
- **依赖说明**：`psycopg2-binary==2.9.9` 对 Alpine (musl) amd64/arm64 均有预编译 wheel，无需额外编译依赖

## CI/CD 工作流

### 触发方式

1. **手动触发** (`workflow_dispatch`)：可指定 `version_tag`（如 `v1.0.0` 或 `latest`）
2. **自动触发** (`push`)：`pg-ocs-sync-worker/**` 或工作流文件自身变更时自动构建，标签 `latest`

### 工作流结构

```yaml
name: Build pg-ddl-sync Image

on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "设定镜像 Tag"
        default: "latest"
  push:
    branches: [main]
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
      - uses: actions/checkout@v6
      - uses: docker/login-action@v3
      - uses: docker/setup-qemu-action@v4
      - uses: docker/setup-buildx-action@v4
      - uses: docker/metadata-action@v6
      - uses: docker/build-push-action@v7
        with:
          context: ./pg-ocs-sync-worker
          file: ./pg-ocs-sync-worker/PgDdlSync.Dockerfile
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### 工作流参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 镜像仓库 | `ghcr.io` | GitHub Container Registry |
| 镜像名称 | `{owner}/pg-ddl-sync` | 与目录名解耦，聚焦功能描述 |
| 构建平台 | `linux/amd64,linux/arm64` | 覆盖 x86 和 ARM |
| 缓存策略 | `type=gha,mode=max` | 使用 GitHub Actions cache |
| 权限 | `contents:read, packages:write` | 最小权限原则 |

### 标签策略

| 触发方式 | 标签值 |
|----------|--------|
| `workflow_dispatch` | 用户输入的 `version_tag` |
| `push` | `latest` |

## CLAUDE.md 更新

在镜像清单表格末尾新增：

```markdown
| `pg-ocs-sync-worker/` | `ghcr.io/{owner}/pg-ddl-sync` | PostgreSQL DDL 同步伴生服务 (Python) |
```
