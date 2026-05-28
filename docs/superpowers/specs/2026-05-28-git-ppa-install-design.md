# Git PPA 安装设计

## 目标

在 fullstack 镜像中通过 git-core PPA 安装最新版 Git，替代系统自带的老版本。

## 方案

使用 `git-core/ppa` PPA 安装最新稳定版 Git，同时引入 `GIT_VERSION` ARG 作为缓存破坏器。

### 变更文件

#### fullstack-image/fullstack.Dockerfile

1. 在全局 ARG 区域（第 4-7 行）添加：
   ```dockerfile
   ARG GIT_VERSION=latest
   ```

2. 在系统基础工具安装步骤（第 78-88 行），保持原有的时区配置顺序不变，在安装 tzdata 并配置时区之后、安装基础依赖之前插入 PPA 步骤：
   - 添加 PPA 源（`add-apt-repository ppa:git-core/ppa`）
   - `apt update` 刷新包索引
   - 安装基础依赖时 `git` 会自动从 PPA 获取最新版而非系统默认老版本
   - `GIT_VERSION` ARG 的值不影响安装逻辑，仅用于破坏 Docker 层缓存

   ```dockerfile
   ARG GIT_VERSION=latest

   RUN apt-get update && \
       apt-get install -y --no-install-recommends tzdata && \
       ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
       apt-get install -y --no-install-recommends software-properties-common && \
       add-apt-repository ppa:git-core/ppa && \
       apt-get update && \
       apt-get install -y --no-install-recommends \
           curl wget git unzip sudo ca-certificates \
           build-essential jq sqlite3 \
           zsh tmux && \
       apt-get clean && rm -rf /var/lib/apt/lists/*
   ```

   注意事项：
   - 保持原有时区配置顺序：先装 tzdata 配时区，再添加 PPA 和安装其他包
   - `software-properties-common`（提供 `add-apt-repository`）需要先于 PPA 添加步骤安装
   - `git` 从 PPA 装最新而非系统默认版本

3. 在 FROM 后的 ARG 区域（第 16-36 行）重新声明 `GIT_VERSION`：
   ```dockerfile
   ARG GIT_VERSION=latest
   ```

#### 不需要变更的文件

- `.github/workflows/build-fullstack.yml` — build_args 已支持传入任意 ARG
- `.github/workflows/build-fullstack-batch.yml` — scenarios.yaml 的 build_args 已支持传入任意 ARG
- `fullstack-image/scenarios.yaml` — 默认值不需要改，想刷缓存时传 `GIT_VERSION=2.54.0` 等

### 缓存更新机制

- 正常构建：`GIT_VERSION` 默认值为 `latest`，走缓存，不重装 git
- 想强制升级 git：在 workflow 中传 `GIT_VERSION=2.54.0`（或任意新值），ARG 变化导致从该层开始重建，触发 `apt install git` 从 PPA 获取最新版
- 升级完成后可恢复为 `GIT_VERSION=latest`

### 不涉及的变更

- 不支持 arm64（PPA 架构限制），fullstack 镜像当前也只构建 linux/amd64
- 不修改 workflow 文件
- 不修改 scenarios.yaml 默认值