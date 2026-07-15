# AKTools 镜像包装与 AKShare 升级

## 概述

创建两个独立的 GitHub Actions 工作流：
1. **包装上游 aktools** — 从阿里云镜像仓库拉取上游 aktools 镜像，重打标签后推送到 ghcr.io
2. **升级 AKShare** — 基于自有 aktools 镜像，通过 Dockerfile 升级 akshare 版本并构建新镜像

## 背景

上游 [akfamily/aktools](https://github.com/akfamily/aktools) 在阿里云镜像仓库 (`registry.cn-shanghai.aliyuncs.com/akfamily/aktools`) 发布预构建镜像。我们需要将其包装到自有 ghcr.io 仓库以保证可用性和统一管理，同时支持在 aktools 基础上独立升级 AKShare Python 包。

## 镜像 Tag 策略

| 镜像 | Tag 格式 | 示例 |
|------|---------|------|
| 包装上游 | `<aktools_version>` | `1.8.95` |
| 升级 AKShare | `<aktools_version>-akshare-<akshare_version>` | `1.8.95-akshare-1.14.90` |

两者共用 `ghcr.io/<owner>/aktools` 镜像名，通过不同 tag 区分。

## 目录结构

```
aktools/
└── aktools-upgrade.Dockerfile   # Workflow 2 的升级 Dockerfile
```

Workflow 1 不需要 Dockerfile（直接 pull + retag + push）。

## 文件清单

| 文件 | 用途 |
|------|------|
| `.github/workflows/build-aktools.yml` | Workflow 1 — 包装上游 aktools |
| `.github/workflows/build-aktools-upgrade.yml` | Workflow 2 — 升级 AKShare |
| `aktools/aktools-upgrade.Dockerfile` | 升级构建用的 Dockerfile |

---

## Workflow 1: 包装上游 aktools (`build-aktools.yml`)

### 构建流程

```
docker pull registry.cn-shanghai.aliyuncs.com/akfamily/aktools:<version>
↓
docker tag <aliyun_image> ghcr.io/<owner>/aktools:<version>
↓
docker push ghcr.io/<owner>/aktools:<version>
```

### 触发方式

- `workflow_dispatch` — 手动指定 `version_tag`（如 `1.8.95`）
- `push` — `aktools/**` 或 workflow 文件变更时自动构建 `latest`

### 多架构

不主动处理多架构。上游阿里云镜像为单一架构，直接透传。如后续上游支持多架构 manifest，拉取后再推送即可保留。

### 边界情况

| 场景 | 处理 |
|------|------|
| 阿里云镜像不存在 | `docker pull` 失败，CI 报错退出 |
| 阿里云不可达 | CI 超时失败，手动重试 |
| tag 已存在于 ghcr.io | `docker push` 覆盖（幂等） |

---

## Workflow 2: 升级 AKShare (`build-aktools-upgrade.yml`)

### Dockerfile (`aktools/aktools-upgrade.Dockerfile`)

```dockerfile
ARG BASE_VERSION=1.8.95
FROM ghcr.io/<owner>/aktools:${BASE_VERSION}

ARG AKSHARE_VERSION
RUN pip install akshare==${AKSHARE_VERSION} -i https://pypi.org/simple
```

### 构建流程

```
docker build \
  --build-arg BASE_VERSION=<aktools_version> \
  --build-arg AKSHARE_VERSION=<akshare_version> \
  -f aktools/aktools-upgrade.Dockerfile \
  -t ghcr.io/<owner>/aktools:<aktools_version>-akshare-<akshare_version> \
  .
↓
docker push ghcr.io/<owner>/aktools:<aktools_version>-akshare-<akshare_version>
```

### 触发方式

- 仅 `workflow_dispatch`，手动指定两个参数：
  - `base_version` — 基础 aktools 版本（必填，如 `1.8.95`）
  - `akshare_version` — 目标 AKShare 版本（必填，如 `1.14.90`）

### 边界情况

| 场景 | 处理 |
|------|------|
| 基础镜像不存在于 ghcr.io | CI `docker build` 阶段失败（FROM 找不到） |
| akshare 版本不存在于 PyPI | pip install 失败，CI 报错 |
| 目标 tag 已存在 | 覆盖（幂等，重新构建以获取最新依赖） |
| AKShare 依赖冲突 | pip install 失败，CI 报错退出，需人工排查 |

---

## 依赖

无需新增 Secret。两个 workflow 仅需：
- `contents: read` — 读取仓库代码
- `packages: write` — 推送镜像到 ghcr.io

## 不涉及

- 定时自动检测 AKShare 新版本（后续可加 cron + PyPI API 检测）
- 镜像健康检查/测试（CLAUDE.md 明确不进行本地测试）
- 多架构构建（上游为单一架构）
