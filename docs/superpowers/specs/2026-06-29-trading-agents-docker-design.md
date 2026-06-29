# TradingAgents Docker 镜像构建设计

## 概述

为 [TauricResearch/TradingAgents](https://github.com/TauricResearch/TradingAgents) 构建自定义 Docker 镜像，纳入 `self-docker-build-image` 仓库的 CI/CD 体系，推送到 `ghcr.io/{owner}/trading-agents`。

上游已提供 Dockerfile（交互式 CLI + `tty`），但我们需要调整为**常驻容器模式**：启动后保持运行，用户随时 `docker exec -it` 进入 CLI 使用。

## 镜像设计

### 镜像名称

`ghcr.io/{owner}/trading-agents`

### 基础镜像

`python:3.12-slim`（与上游保持一致）

### 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `TRADINGAGENTS_VERSION` | `main` | 上游 Git tag 或分支名 |

### Dockerfile (`trading-agents/TradingAgents.Dockerfile`)

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

### 关键设计决策

1. **`sleep infinity` 保活** — 零 CPU 开销，容器常驻运行，用户通过 `docker exec -it <container> tradingagents` 随时进入 CLI
2. **git clone + rm .git** — 精确锁定上游版本，清理 `.git` 减小镜像体积
3. **非 root 用户** — `appuser` 运行，数据目录挂载到 `/home/appuser/.tradingagents`
4. **不嵌入上游 Dockerfile** — 上游的 Dockerfile 逻辑简单（venv + pip install + useradd），自己写成本极低且完全可控

## CI/CD 设计

### 触发方式

| 触发 | 条件 | `TRADINGAGENTS_VERSION` |
|------|------|--------------------------|
| `workflow_dispatch` | 手动触发 | `inputs.version_tag`（默认 `main`）|
| `push` | `trading-agents/**` 或 workflow 文件变更 | `main` |

### Workflow 文件

`.github/workflows/build-trading-agents.yml`

沿用仓库标准模板：
- `docker/setup-qemu-action@v4` — 多架构支持
- `docker/setup-buildx-action@v4` — Buildx
- `docker/metadata-action@v6` — 标签生成
- `docker/build-push-action@v7` — 构建推送
- 多架构：`linux/amd64,linux/arm64`
- GHA 缓存：`type=gha,mode=max`

### 安全

- 权限最小化：`contents: read, packages: write`
- Pre-commit hooks 包含 gitleaks 检测

## 使用方式

```bash
# 启动（一次性）
docker run -d --name trading-agents \
  -e OPENAI_API_KEY=xxx \
  -e ANTHROPIC_API_KEY=xxx \
  -v trading-agents-data:/home/appuser/.tradingagents \
  ghcr.io/{owner}/trading-agents:v0.3.0

# 随时使用 CLI
docker exec -it trading-agents tradingagents
```

## 方案选型背景

共评估 5 种方案：

| 方案 | 特点 | 是否采用 |
|------|------|----------|
| A. 自定义 Dockerfile + git clone | 完全控制，模式一致 | ✅ 采用 |
| B. CI 中直接构建上游 Dockerfile | 零维护，不可定制 | ❌ |
| C. pip install git+https | 最简，网络不稳定 | ❌ |
| D. 多阶段复用上游 Dockerfile | 耦合上游，维护成本高 | ❌ |
| E. Git submodule | 管理复杂 | ❌ |

选 A 的理由：与仓库现有 `cosyvoice`、`glm-coding-grabber` 模式一致，完全可控，CI 集成自然。
