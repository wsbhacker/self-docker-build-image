# Refactor Fullstack Dockerfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Dockerfile to create neo user early with sudo, install all tools as neo, and remove redundant root Oh My Zsh.

**Architecture:** Two-phase structure: root phase (apt-get, neo user creation with sudo) → neo phase (directory structure, all tool installations, Oh My Zsh). Tools relocate from system directories to neo's home (~/.local/bin, ~/opt).

**Tech Stack:** Docker, Ubuntu 22.04 (Jammy), zsh/Oh My Zsh, Maven, Node.js, Neovim, chezmoi, uv, Claude Code

---

## File Structure

**Modify:** `fullstack-image/fullstack.Dockerfile`

The Dockerfile will be restructured from:
- Current: root installs all → root creates neo → neo installs Claude Code
- Target: root apt-get → root creates neo with sudo → neo creates dirs → neo installs all tools → neo Oh My Zsh

---

## Task 1: Update PATH Configuration for neo

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:41`

**Current PATH:**
```dockerfile
ENV PATH="/root/.local/bin:/opt/maven/bin:/opt/nvim-linux-x86_64/bin:${PATH}"
```

**New PATH:**
```dockerfile
ENV PATH="/home/neo/.local/bin:/home/neo/.local/node/bin:/home/neo/opt/maven/bin:/home/neo/opt/nvim/bin:${PATH}"
```

- [ ] **Step 1: Edit PATH ENV directive**

Change line 41:

```dockerfile
ENV PATH="/home/neo/.local/bin:/home/neo/.local/node/bin:/home/neo/opt/maven/bin:/home/neo/opt/nvim/bin:${PATH}"
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: update PATH to neo's tool directories"
```

---

## Task 2: Remove root's Oh My Zsh Installation

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:105-111` (delete)

**Block to remove:**
```dockerfile
# ==========================================
# 8. 配置 Zsh + Oh My Zsh
# ==========================================
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' ~/.zshrc && \
    echo "alias vim='nvim'" >> ~/.zshrc && \
    echo "alias vi='nvim'" >> ~/.zshrc
```

- [ ] **Step 1: Delete lines 103-111 (section header + RUN block)**

Remove the entire Oh My Zsh installation block for root.

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: remove redundant root Oh My Zsh installation"
```

---

## Task 3: Restructure Neo User Creation with Sudo

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:113-129`

**Current block:**
```dockerfile
# ==========================================
# 9. 创建 neo 用户（非 root）
# ==========================================
# 创建用户组并指定 GID，创建用户并指定 UID/GID（支持与宿主机用户匹配）
RUN groupadd -g ${USER_GID} neo && \
    useradd -m -s /bin/zsh -u ${USER_UID} -g neo neo && \
    # 为 neo 安装 Oh My Zsh (使用 --unattended 非交互模式)
    su - neo -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' && \
    # 安装 zsh 插件 (root 执行，需 chown)
    git clone https://github.com/zsh-users/zsh-autosuggestions /home/neo/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting /home/neo/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    chown -R neo:neo /home/neo/.oh-my-zsh/custom/plugins && \
    # 配置 .zshrc
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /home/neo/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' /home/neo/.zshrc && \
    echo "alias vim='nvim'" >> /home/neo/.zshrc && \
    echo "alias vi='nvim'" >> /home/neo/.zshrc
```

**New block (simplified, Oh My Zsh moved to neo phase):**
```dockerfile
# ==========================================
# 8. 创建 neo 用户（非 root）并配置 sudo
# ==========================================
# 创建用户组并指定 GID，创建用户并指定 UID/GID（支持与宿主机用户匹配）
RUN groupadd -g ${USER_GID} neo && \
    useradd -m -s /bin/zsh -u ${USER_UID} -g neo neo && \
    # 配置 NOPASSWD sudo 权限
    echo "neo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/neo && \
    chmod 0440 /etc/sudoers.d/neo
```

- [ ] **Step 1: Replace neo user creation block**

Replace lines 113-129 with:

```dockerfile
# ==========================================
# 8. 创建 neo 用户（非 root）并配置 sudo
# ==========================================
# 创建用户组并指定 GID，创建用户并指定 UID/GID（支持与宿主机用户匹配）
RUN groupadd -g ${USER_GID} neo && \
    useradd -m -s /bin/zsh -u ${USER_UID} -g neo neo && \
    # 配置 NOPASSWD sudo 权限
    echo "neo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/neo && \
    chmod 0440 /etc/sudoers.d/neo
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: add NOPASSWD sudo for neo, move Oh My Zsh to neo phase"
```

---

## Task 4: Add USER neo and Directory Structure

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile` (insert after Task 3)

- [ ] **Step 1: Add USER neo and directory creation block**

Insert after neo user creation:

```dockerfile

# ==========================================
# 9. 切换到 neo 用户
# ==========================================
USER neo

# ==========================================
# 10. 创建 neo 目录结构
# ==========================================
RUN mkdir -p ~/.local/bin ~/.local/share ~/opt ~/work
```

**Note:** Create `~/opt` only (not `~/opt/maven` or `~/opt/nvim`) because the tar extracts will create their own subdirs, then symlinks point to them.

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: add USER neo with directory structure"
```

---

## Task 5: Add Oh My Zsh Installation for neo

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile` (insert after Task 4)

- [ ] **Step 1: Add Oh My Zsh block for neo**

Insert after directory creation:

```dockerfile

# ==========================================
# 11. 配置 Zsh + Oh My Zsh (neo 用户)
# ==========================================
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' ~/.zshrc && \
    echo "alias vim='nvim'" >> ~/.zshrc && \
    echo "alias vi='nvim'" >> ~/.zshrc
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move Oh My Zsh to neo phase"
```

---

## Task 6: Move Maven Installation to neo's ~/opt

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:67-73` (delete original)
- Insert new block after Oh My Zsh

**Original block (lines 67-73):**
```dockerfile
# ==========================================
# 3. 精确安装指定版本的 Maven
# ==========================================
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar xzf /tmp/maven.tar.gz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven && \
    rm /tmp/maven.tar.gz
```

- [ ] **Step 1: Delete original Maven block**

Remove lines 67-73 (section header + RUN).

- [ ] **Step 2: Add Maven block for neo**

Insert after Oh My Zsh:

```dockerfile

# ==========================================
# 12. 精确安装指定版本的 Maven (neo 用户)
# ==========================================
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar xzf /tmp/maven.tar.gz -C ~/opt && \
    ln -s ~/opt/apache-maven-${MAVEN_VERSION} ~/opt/maven && \
    rm /tmp/maven.tar.gz
```

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move Maven to neo ~/opt/maven"
```

---

## Task 7: Move Node.js Installation to neo's ~/.local

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:75-81` (delete original)
- Insert new block after Maven

**Original block (lines 75-81):**
```dockerfile
# ==========================================
# 4. 精确安装指定版本的 Node.js, pnpm 和 yarn
# ==========================================
RUN wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -O /tmp/nodejs.tar.xz && \
    tar -xJf /tmp/nodejs.tar.xz -C /usr/local --strip-components=1 && \
    rm /tmp/nodejs.tar.xz && \
    npm install -g pnpm@${PNPM_VERSION} yarn@${YARN_VERSION}
```

- [ ] **Step 1: Delete original Node.js block**

Remove lines 75-81.

- [ ] **Step 2: Add Node.js block for neo**

Insert after Maven:

```dockerfile

# ==========================================
# 13. 精确安装指定版本的 Node.js, pnpm 和 yarn (neo 用户)
# ==========================================
RUN wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -O /tmp/nodejs.tar.xz && \
    mkdir -p ~/.local/node && \
    tar -xJf /tmp/nodejs.tar.xz -C ~/.local/node --strip-components=1 && \
    rm /tmp/nodejs.tar.xz && \
    ~/.local/node/bin/npm install -g pnpm@${PNPM_VERSION} yarn@${YARN_VERSION}
```

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move Node.js to neo ~/.local/node"
```

---

## Task 8: Move uv Installation to neo's ~/.local

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:83-86` (delete original)
- Insert new block after Node.js

**Original block:**
```dockerfile
# ==========================================
# 5. 精确安装指定版本的 uv (极速 Python 包管理器)
# ==========================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_VERSION=${UV_VERSION} sh
```

**Note:** uv install script automatically installs to `~/.local/bin` when run as non-root user.

- [ ] **Step 1: Delete original uv block**

Remove lines 83-86.

- [ ] **Step 2: Add uv block for neo**

Insert after Node.js:

```dockerfile

# ==========================================
# 14. 精确安装指定版本的 uv (neo 用户)
# ==========================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_VERSION=${UV_VERSION} sh
```

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move uv to neo ~/.local/bin"
```

---

## Task 9: Move Neovim Installation to neo's ~/opt

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:88-93` (delete original)
- Insert new block after uv

**Original block:**
```dockerfile
# ==========================================
# 6. 精确安装现代版 Neovim (官方预编译二进制包)
# ==========================================
RUN wget https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C /opt && \
    rm /tmp/nvim.tar.gz
```

- [ ] **Step 1: Delete original Neovim block**

Remove lines 88-93.

- [ ] **Step 2: Add Neovim block for neo**

Insert after uv:

```dockerfile

# ==========================================
# 15. 精确安装现代版 Neovim (neo 用户)
# ==========================================
RUN wget https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C ~/opt && \
    ln -s ~/opt/nvim-linux-x86_64 ~/opt/nvim && \
    rm /tmp/nvim.tar.gz
```

**Note:** Use symlink `~/opt/nvim` pointing to `~/opt/nvim-linux-x86_64` for cleaner PATH.

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move Neovim to neo ~/opt/nvim"
```

---

## Task 10: Move chezmoi Installation to neo's ~/.local

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:95-100` (delete original)
- Insert new block after Neovim

**Original block:**
```dockerfile
# ==========================================
# 7. 精确安装指定版本的 chezmoi (dotfiles 管理工具)
# ==========================================
RUN wget https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz -O /tmp/chezmoi.tar.gz && \
    tar -xzf /tmp/chezmoi.tar.gz -C /usr/local/bin chezmoi && \
    rm /tmp/chezmoi.tar.gz
```

- [ ] **Step 1: Delete original chezmoi block**

Remove lines 95-100.

- [ ] **Step 2: Add chezmoi block for neo**

Insert after Neovim:

```dockerfile

# ==========================================
# 16. 精确安装指定版本的 chezmoi (neo 用户)
# ==========================================
RUN wget https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz -O /tmp/chezmoi.tar.gz && \
    tar -xzf /tmp/chezmoi.tar.gz -C ~/.local/bin chezmoi && \
    rm /tmp/chezmoi.tar.gz
```

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: move chezmoi to neo ~/.local/bin"
```

---

## Task 11: Clean Up Duplicate Sections

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile` (remove duplicates after restructure)

**Duplicate sections to remove:**

Current lines (after all moves, approximately 130-135):
```dockerfile
# ==========================================
# 10. 切换到 neo 用户
# ==========================================
USER neo
RUN mkdir -p /home/neo/work
```

These are now duplicates because we added USER neo and mkdir in Task 4.

- [ ] **Step 1: Remove duplicate USER neo block**

Find and remove the old USER neo section (it will be after chezmoi in original structure).

- [ ] **Step 2: Update Claude Code section comment**

Change section number from 11 to 17:

```dockerfile
# ==========================================
# 17. 为 neo 用户安装 Claude Code
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash
```

- [ ] **Step 3: Verify final WORKDIR, ENV SHELL, CMD preserved**

Ensure these remain:

```dockerfile
WORKDIR /home/neo/work
ENV SHELL=/bin/zsh
CMD ["sleep", "infinity"]
```

- [ ] **Step 4: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "refactor: clean up duplicate sections"
```

---

## Task 12: Final Verification

**Files:**
- Verify: `fullstack-image/fullstack.Dockerfile`

- [ ] **Step 1: Read final Dockerfile and verify structure**

Expected structure:
```
Section 0: ARG JDK_VERSION (before FROM)
FROM eclipse-temurin
Section 1: ARG declarations (MAVEN_VERSION, NODE_VERSION, etc.)
Section 2: ENV declarations (including PATH for neo)
Section 3: apt-get (system packages with sudo)
Section 8: Neo user creation + sudo config
Section 9: USER neo
Section 10: mkdir ~/.local/bin, ~/.local/share, ~/opt, ~/work
Section 11: Oh My Zsh for neo
Section 12: Maven for neo
Section 13: Node.js for neo
Section 14: uv for neo
Section 15: Neovim for neo
Section 16: chezmoi for neo
Section 17: Claude Code for neo
Final: WORKDIR, ENV SHELL, CMD
```

- [ ] **Step 2: Squash commits or create final commit**

Option A: Keep all commits (detailed history)
Option B: Squash to single commit:

```bash
git reset --soft HEAD~11
git commit -m "refactor: restructure Dockerfile for neo-user-first approach

- Move neo user creation after apt-get with NOPASSWD sudo
- Relocate all tools to neo's home (~/.local/bin, ~/opt)
- Remove redundant root Oh My Zsh installation
- Update PATH ENV for neo's tool locations
- Restructure sections: root phase (apt-get, neo creation) -> neo phase (all tools)"
```

---

## Self-Review Checklist

### 1. Spec Coverage

| Spec Requirement | Task Coverage |
|-----------------|---------------|
| Neo user created with correct UID/GID | Task 3 |
| Neo has NOPASSWD sudo | Task 3 |
| Directory structure exists | Task 4 |
| PATH configured for neo tools | Task 1 |
| Tools executable without full path | Verified by PATH |
| Tools owned by neo | All neo-phase tasks (6-10) |
| Oh My Zsh for neo only | Task 2 (remove root), Task 5 (add neo) |
| Claude Code for neo | Task 11 (preserved) |

### 2. Placeholder Scan

- ✓ No TBD, TODO, or "implement later"
- ✓ All code blocks show exact content
- ✓ All file paths are exact
- ✓ All commands are exact

### 3. Type Consistency

- PATH uses `/home/neo/` (ENV doesn't expand ~)
- RUN commands use `~` (shell expands)
- All tool directories consistent: `~/.local/bin`, `~/.local/node`, `~/opt/maven`, `~/opt/nvim`

---

## Complete Refactored Dockerfile (Final State)

```dockerfile
# ==========================================
# 0. 定义全局构建参数 (可动态指定各软件版本)
# ==========================================
ARG JDK_VERSION=8

# 使用 Eclipse Temurin 官方 JDK 镜像 (基于坚如磐石的 Ubuntu 22.04 Jammy)
FROM eclipse-temurin:${JDK_VERSION}-jdk-jammy

# 在 FROM 后重新声明 ARG 以接收外部 build-arg
ARG MAVEN_VERSION=3.9.9
ARG NODE_VERSION=20.18.0
ARG PYTHON_VERSION=3.11
ARG UV_VERSION=0.5.21
ARG PNPM_VERSION=9.12.3
ARG YARN_VERSION=1.22.22
ARG NEOVIM_VERSION=0.11.6
ARG CHEZMOI_VERSION=2.70.0
ARG USER_UID=1000
ARG USER_GID=1000

# 设置环境变量，防止 apt 交互式安装卡住
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ==========================================
# 1. 将构建参数转为环境变量 (供后续使用)
# ==========================================
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV NODE_VERSION=${NODE_VERSION}
ENV PYTHON_VERSION=${PYTHON_VERSION}
ENV UV_VERSION=${UV_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}
ENV YARN_VERSION=${YARN_VERSION}
ENV NEOVIM_VERSION=${NEOVIM_VERSION}
ENV CHEZMOI_VERSION=${CHEZMOI_VERSION}
ENV USER_UID=${USER_UID}
ENV USER_GID=${USER_GID}

# 配置全局 PATH (neo 用户路径)
ENV PATH="/home/neo/.local/bin:/home/neo/.local/node/bin:/home/neo/opt/maven/bin:/home/neo/opt/nvim/bin:${PATH}"

# ==========================================
# 2. 安装系统基础工具、配置时区及 Python
# ==========================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get install -y --no-install-recommends \
        software-properties-common curl wget git unzip sudo ca-certificates \
        build-essential jq ripgrep sqlite3 \
        zsh tmux && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# 8. 创建 neo 用户（非 root）并配置 sudo
# ==========================================
RUN groupadd -g ${USER_GID} neo && \
    useradd -m -s /bin/zsh -u ${USER_UID} -g neo neo && \
    echo "neo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/neo && \
    chmod 0440 /etc/sudoers.d/neo

# ==========================================
# 9. 切换到 neo 用户
# ==========================================
USER neo

# ==========================================
# 10. 创建 neo 目录结构
# ==========================================
RUN mkdir -p ~/.local/bin ~/.local/share ~/opt ~/work

# ==========================================
# 11. 配置 Zsh + Oh My Zsh (neo 用户)
# ==========================================
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' ~/.zshrc && \
    echo "alias vim='nvim'" >> ~/.zshrc && \
    echo "alias vi='nvim'" >> ~/.zshrc

# ==========================================
# 12. 精确安装指定版本的 Maven (neo 用户)
# ==========================================
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar xzf /tmp/maven.tar.gz -C ~/opt && \
    ln -s ~/opt/apache-maven-${MAVEN_VERSION} ~/opt/maven && \
    rm /tmp/maven.tar.gz

# ==========================================
# 13. 精确安装指定版本的 Node.js, pnpm 和 yarn (neo 用户)
# ==========================================
RUN wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -O /tmp/nodejs.tar.xz && \
    mkdir -p ~/.local/node && \
    tar -xJf /tmp/nodejs.tar.xz -C ~/.local/node --strip-components=1 && \
    rm /tmp/nodejs.tar.xz && \
    ~/.local/node/bin/npm install -g pnpm@${PNPM_VERSION} yarn@${YARN_VERSION}

# ==========================================
# 14. 精确安装指定版本的 uv (neo 用户)
# ==========================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_VERSION=${UV_VERSION} sh

# ==========================================
# 15. 精确安装现代版 Neovim (neo 用户)
# ==========================================
RUN wget https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C ~/opt && \
    ln -s ~/opt/nvim-linux-x86_64 ~/opt/nvim && \
    rm /tmp/nvim.tar.gz

# ==========================================
# 16. 精确安装指定版本的 chezmoi (neo 用户)
# ==========================================
RUN wget https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz -O /tmp/chezmoi.tar.gz && \
    tar -xzf /tmp/chezmoi.tar.gz -C ~/.local/bin chezmoi && \
    rm /tmp/chezmoi.tar.gz

# ==========================================
# 17. 为 neo 用户安装 Claude Code
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /home/neo/work
ENV SHELL=/bin/zsh
CMD ["sleep", "infinity"]
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-09-refactor-fullstack-dockerfile.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**