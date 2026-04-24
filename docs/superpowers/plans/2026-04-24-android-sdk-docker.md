# Android SDK Docker Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the fullstack Docker image with Android SDK support for building Android APKs (arm64-v8a).

**Architecture:** Runtime SDK installation via entrypoint script. The Docker image provides environment setup (paths, directories), while the actual SDK components are downloaded on first container start to a mounted volume for persistence and flexibility.

**Tech Stack:** Docker, Android cmdline-tools, sdkmanager, Bash entrypoint script

---

## File Structure

| File | Responsibility |
|------|---------------|
| `fullstack-image/fullstack.Dockerfile` | Android environment variables, PATH, SDK directory creation |
| `fullstack-image/entrypoint.sh` | SDK detection, download, installation, license acceptance |

---

### Task 1: Add Android ARG Variables to Dockerfile

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:4-6` (global ARG section)
- Modify: `fullstack-image/fullstack.Dockerfile:15-27` (post-FROM ARG section)

- [ ] **Step 1: Add global ARG for cmdline-tools version**

Add after line 6 (`ARG CLAUDE_VERSION=latest`):

```dockerfile
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
```

- [ ] **Step 2: Add post-FROM ARG for platform and build-tools**

Add after line 27 (`ARG USERNAME=neo`):

```dockerfile
ARG TARGET_PLATFORM=android-34
ARG BUILD_TOOLS_VERSION=34.0.0
```

- [ ] **Step 3: Verify ARG placement**

Run: `grep -n "ARG" fullstack-image/fullstack.Dockerfile | head -20`
Expected: Shows ANDROID_CMDLINE_TOOLS_VERSION at global section, TARGET_PLATFORM and BUILD_TOOLS_VERSION after FROM

- [ ] **Step 4: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(android): add Android SDK ARG variables to Dockerfile"
```

---

### Task 2: Add Android ENV Variables to Dockerfile

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:50-51` (ENV section)

- [ ] **Step 1: Add ANDROID_HOME environment variables**

Add after line 51 (`ENV HOME=/home/${USERNAME}`):

```dockerfile
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION}
ENV TARGET_PLATFORM=${TARGET_PLATFORM}
ENV BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION}
```

- [ ] **Step 2: Verify ENV placement**

Run: `grep -n "ENV ANDROID" fullstack-image/fullstack.Dockerfile`
Expected: Shows 5 Android-related ENV lines

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(android): add Android SDK ENV variables"
```

---

### Task 3: Update PATH to Include Android SDK Directories

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:54` (PATH ENV)

- [ ] **Step 1: Modify PATH to include Android SDK paths**

Replace line 54:

```dockerfile
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

- [ ] **Step 2: Verify PATH update**

Run: `grep -n "ENV PATH" fullstack-image/fullstack.Dockerfile`
Expected: Single line containing ANDROID_HOME paths

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(android): add Android SDK paths to PATH"
```

---

### Task 4: Create Android SDK Directory in Dockerfile

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:104` (directory creation section)

- [ ] **Step 1: Add RUN command to create Android SDK directory**

Add after line 104 (`RUN mkdir -p ~/.local/bin ~/.local/share ~/opt ~/work`):

```dockerfile

# ==========================================
# 11. 创建 Android SDK 目录
# ==========================================
USER root
RUN mkdir -p ${ANDROID_HOME} && \
    chown -R ${USERNAME}:${USERNAME} ${ANDROID_HOME}
USER ${USERNAME}
```

- [ ] **Step 2: Verify directory creation**

Run: `grep -n "ANDROID_HOME" fullstack-image/fullstack.Dockerfile`
Expected: Shows directory creation RUN command with proper ownership

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(android): create Android SDK directory with proper ownership"
```

---

### Task 5: Add Android SDK Installation Logic to Entrypoint

**Files:**
- Modify: `fullstack-image/entrypoint.sh:21-22` (after Oh My Zsh block, before exec)

- [ ] **Step 1: Add Android SDK check and installation function**

Add after line 20 (`fi` of Oh My Zsh block), before `exec "$@"`:

```bash

# 检查并安装 Android SDK
if [ ! -f "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Installing Android SDK..."

  # 确保目录权限
  sudo chown -R ${USERNAME}:${USERNAME} ${ANDROID_HOME} 2>/dev/null || true

  # 下载 cmdline-tools
  ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION:-14742923}
  wget https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip \
    -O /tmp/cmdline-tools.zip

  # 解压并安装
  mkdir -p ${ANDROID_HOME}/cmdline-tools
  unzip /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools
  mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest
  rm /tmp/cmdline-tools.zip

  # 接受许可证
  yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1 || true

  # 安装 SDK 组件
  ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
    "platforms;${TARGET_PLATFORM:-android-34}" \
    "build-tools;${BUILD_TOOLS_VERSION:-34.0.0}" \
    "platform-tools"
fi
```

- [ ] **Step 2: Verify entrypoint content**

Run: `grep -n "ANDROID" fullstack-image/entrypoint.sh`
Expected: Shows sdkmanager check and installation block

- [ ] **Step 3: Commit**

```bash
git add fullstack-image/entrypoint.sh
git commit -m "feat(android): add Android SDK runtime installation to entrypoint"
```

---

### Task 6: Update Documentation

**Files:**
- Modify: `CLAUDE.md` (update镜像清单)

- [ ] **Step 1: Add fullstack-android entry to镜像清单**

Add a new row in the镜像清单 table:

```markdown
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装) |
```

- [ ] **Step 2: Verify documentation**

Run: `grep "fullstack-image" CLAUDE.md`
Expected: Shows fullstack entry with Android SDK description

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add fullstack-android to镜像清单"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- ✓ ARG ANDROID_CMDLINE_TOOLS_VERSION (Task 1)
- ✓ ARG TARGET_PLATFORM, BUILD_TOOLS_VERSION (Task 1)
- ✓ ENV ANDROID_HOME, ANDROID_SDK_ROOT (Task 2)
- ✓ ENV for version variables (Task 2)
- ✓ PATH modification (Task 3)
- ✓ Directory creation with ownership (Task 4)
- ✓ Entrypoint SDK installation logic (Task 5)
- ✓ GitHub workflow (no modification needed - already supports build-args)

**2. Placeholder scan:**
- No TBD, TODO, or placeholder patterns found
- All code blocks contain complete implementation

**3. Type consistency:**
- `ANDROID_HOME` used consistently across Dockerfile and entrypoint
- `TARGET_PLATFORM`, `BUILD_TOOLS_VERSION`, `ANDROID_CMDLINE_TOOLS_VERSION` consistent naming
- `${USERNAME}` variable used correctly for ownership

