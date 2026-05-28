# Git PPA 安装 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 fullstack 镜像中通过 git-core PPA 安装最新版 Git，同时引入 GIT_VERSION ARG 作为缓存破坏器。

**Architecture:** 修改 fullstack.Dockerfile，添加 GIT_VERSION ARG（两处：FROM 前和 FROM 后），在系统包安装步骤中先装 tzdata 配时区（保持原顺序），再安装 software-properties-common，添加 git-core PPA，刷新索引，最后安装所有包（git 自动从 PPA 获取最新版）。

**Tech Stack:** Dockerfile, GitHub Actions

---

### Task 1: 添加 GIT_VERSION ARG 声明

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:4-7` (FROM 前全局 ARG 区域)
- Modify: `fullstack-image/fullstack.Dockerfile:16-36` (FROM 后 ARG 重新声明区域)

- [ ] **Step 1: 在 FROM 前添加全局 ARG**

在 `fullstack-image/fullstack.Dockerfile` 第 7 行后添加：

```dockerfile
ARG GIT_VERSION=latest
```

修改后第 4-8 行应为：

```dockerfile
ARG JDK_VERSION=8
ARG PYTHON_VERSION=3.12
ARG CLAUDE_VERSION=latest
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
ARG GIT_VERSION=latest
```

- [ ] **Step 2: 在 FROM 后重新声明 ARG**

在 `fullstack-image/fullstack.Dockerfile` 第 36 行后（`ANDROID_CMDLINE_TOOLS_VERSION` 之后）添加：

```dockerfile
ARG GIT_VERSION=latest
```

这是 Docker ARG 作用域机制要求的：FROM 前声明的 ARG 在 FROM 后不可见，需要重新声明。

- [ ] **Step 3: 提交 ARG 变更**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat: add GIT_VERSION ARG to fullstack Dockerfile"
```

---

### Task 2: 修改系统包安装步骤，添加 PPA

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:78-88` (系统基础工具安装步骤)

- [ ] **Step 1: 替换 apt 安装 RUN 指令**

将第 78-88 行的 RUN 指令替换为以下内容（保持时区配置顺序不变，插入 PPA 步骤）：

```dockerfile
RUN apt-get update && \
    # --- 修改：安装 tzdata 并立即配置时区 ---
    apt-get install -y --no-install-recommends tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # 安装 software-properties-common（提供 add-apt-repository）
    apt-get install -y --no-install-recommends software-properties-common && \
    # 添加 git-core PPA 以获取最新版 git
    add-apt-repository ppa:git-core/ppa && \
    apt-get update && \
    # 安装基础依赖（git 将从 PPA 获取最新版）
    apt-get install -y --no-install-recommends \
        curl wget git unzip sudo ca-certificates \
        build-essential jq sqlite3 \
        zsh tmux && \
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

关键变更点：
- 原来第 84 行 `software-properties-common curl wget git unzip sudo ca-certificates` 在一个 apt install 里，现在 `software-properties-common` 单独先装（因为 `add-apt-repository` 需要它）
- 在 `add-apt-repository ppa:git-core/ppa` 和第二次 `apt-get update` 之后，其余包才安装
- 时区配置（tzdata 安装 + ln -snf）保持原位置不变

- [ ] **Step 2: 提交 PPA 安装变更**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat: add git-core PPA to install latest git version"
```

---

### Task 3: 更新 CLAUDE.md 镜像清单

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: 更新 fullstack-image 的说明**

在 CLAUDE.md 的镜像清单表中，`fullstack-image/` 行的说明列，添加 Git PPA 相关信息：

将：
```
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装) |
```

改为：
```
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装), Git via PPA |
```

- [ ] **Step 2: 提交 CLAUDE.md 更新**

```bash
git add CLAUDE.md
git commit -m "docs: update fullstack image description with Git PPA"
```