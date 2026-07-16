# AKTools 镜像构建 v2

## 概述

基于 [akfamily/aktools](https://github.com/akfamily/aktools) 源码仓库构建 Docker 镜像，推送到 ghcr.io。使用自定义 Dockerfile + requirements.txt 替代上游的依赖管理方式，精确控制 akshare 等依赖版本。

## 与 v1（已 revert）的区别

| 项目 | v1 | v2 |
|------|----|----|
| 基础镜像来源 | 阿里云镜像仓库拉取 | 从 aktools 源码 checkout + 构建 |
| Dockerfile | 仅升级 akshare（FROM 上游镜像） | 完整构建（FROM python:3.13-slim） |
| akshare 版本控制 | workflow 输入参数 | requirements.txt 固定 |
| 工作流数量 | 2 个（mirror + upgrade） | 1 个 |
| Tag 格式 | `<v>-akshare-<v>` | `<v>-share-<v>` |
| 触发方式 | dispatch + push | 仅 dispatch |

## 文件清单

| 文件 | 用途 |
|------|------|
| `aktools/Aktools.Dockerfile` | 构建用的 Dockerfile |
| `aktools/requirements.txt` | 固定依赖（含 akshare 精确版本） |
| `.github/workflows/build-aktools.yml` | 手动构建 workflow |

## 镜像 Tag 策略

```
ghcr.io/{owner}/aktools:<aktools_version>-share-<akshare_version>
```

示例：`ghcr.io/0xW5B/aktools:0.0.91-share-1.16.25`

akshare 版本号从 `aktools/requirements.txt` 解析获取（单一数据源），aktools 版本号由 workflow 输入。

---

## Dockerfile (`aktools/Aktools.Dockerfile`)

```dockerfile
FROM python:3.13-slim-bullseye

RUN pip install --upgrade pip

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . /aktools-src
RUN pip install --no-cache-dir --no-deps /aktools-src

WORKDIR /usr/local/lib/python3.13/site-packages/aktools
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app", "-k", "uvicorn.workers.UvicornWorker"]
```

### 构建步骤说明

1. `pip install -r requirements.txt` — 安装所有依赖（含 akshare），版本由 requirements.txt 精确 pin 住
2. `pip install --no-deps /aktools-src` — 从本地源码安装 aktools，`--no-deps` 防止 setup.py 的 `install_requires`（`akshare>=1.16.25` 等）覆盖已 pin 的版本

### 构建上下文

构建上下文为 `aktools/` 目录。Dockerfile 中的 `COPY . /aktools-src` 复制的是 aktools 源码（通过第二个 checkout 步骤放入构建上下文）。

---

## Workflow (`build-aktools.yml`)

### 触发方式

仅 `workflow_dispatch`，输入参数：

| 参数 | 必填 | 说明 | 示例 |
|------|------|------|------|
| `aktools_version` | 是 | aktools 上游 tag | `v0.0.91` |

### 构建流程

```
1. checkout self-docker-build-image @ main
   → 拿到 aktools/Aktools.Dockerfile + aktools/requirements.txt

2. checkout akfamily/aktools @ ${{ aktools_version }}
   → 源码放入构建上下文（aktools/ 目录下）

3. 解析 requirements.txt → 提取 akshare 版本号

4. docker build
   -f aktools/Aktools.Dockerfile
   -t ghcr.io/{owner}/aktools:<aktools_version>-share-<akshare_version>
   aktools/

5. docker push
```

### 架构

单架构 `linux/amd64`。上游镜像为单一架构，保持一致。

### 权限

```yaml
permissions:
  contents: read
  packages: write
```

---

## 边界情况

| 场景 | 处理 |
|------|------|
| aktools tag 不存在 | `checkout` 失败，CI 报错退出 |
| akshare 版本不存在于 PyPI | `pip install` 失败，构建报错 |
| 目标 tag 已存在 | docker push 覆盖（幂等） |
| 依赖冲突 | `pip install` 阶段失败，需人工排查 |
| aktools 新版不兼容旧 akshare | 构建通过但运行时可能报错，由使用者保证版本兼容 |

## 不涉及

- 定时自动检测 akshare/aktools 新版本
- 镜像健康检查/测试（CLAUDE.md 明确不进行本地测试）
- 多架构构建
- push 自动触发
