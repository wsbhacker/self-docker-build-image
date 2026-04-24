# Gradle Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Gradle installation support to fullstack-image Docker image for Java/Kotlin project builds.

**Architecture:** Add Gradle as a system-level build tool alongside Maven, installed at `~/opt/gradle` with version controlled via `GRADLE_VERSION` ARG.

**Tech Stack:** Docker, Gradle 9.x, wget, unzip

---

## Files to Modify

| File | Purpose |
|------|---------|
| `fullstack-image/fullstack.Dockerfile` | Add Gradle ARG, ENV, installation step, and PATH update |

---

### Task 1: Add GRADLE_VERSION ARG Declaration

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:16-17`

- [ ] **Step 1: Add GRADLE_VERSION ARG after MAVEN_VERSION**

Add the ARG declaration in the ARG block after MAVEN_VERSION:

```dockerfile
ARG MAVEN_VERSION=3.9.9
ARG GRADLE_VERSION=9.4.1
ARG NODE_VERSION=20.18.0
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add GRADLE_VERSION ARG declaration"
```

---

### Task 2: Add GRADLE_VERSION Environment Variable

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:41`

- [ ] **Step 1: Add GRADLE_VERSION ENV after MAVEN_VERSION**

Add the ENV declaration in the ENV block after MAVEN_VERSION:

```dockerfile
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV GRADLE_VERSION=${GRADLE_VERSION}
ENV NODE_VERSION=${NODE_VERSION}
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add GRADLE_VERSION environment variable"
```

---

### Task 3: Add Gradle Installation Step

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:130` (after Maven installation)

- [ ] **Step 1: Add Gradle installation after Maven installation block**

Insert after the Maven installation block (after line 129 `rm /tmp/maven.tar.gz`):

```dockerfile
# ==========================================
# 12.5. 精确安装指定版本的 Gradle (neo 用户)
# ==========================================
RUN wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -O /tmp/gradle.zip && \
    unzip /tmp/gradle.zip -d ~/opt && \
    mv ~/opt/gradle-${GRADLE_VERSION} ~/opt/gradle && \
    rm /tmp/gradle.zip
```

**Note:** Gradle uses `.zip` format, requiring `unzip` instead of `tar`. The `unzip` package is already installed in step 2 (line 74).

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add Gradle installation step"
```

---

### Task 4: Update PATH to Include Gradle bin

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:63`

- [ ] **Step 1: Add ~/opt/gradle/bin to PATH**

Update the PATH ENV to include Gradle bin directory. Insert after `~/opt/maven/bin`:

```dockerfile
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

- [ ] **Step 2: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add Gradle bin to PATH"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ GRADLE_VERSION ARG with default 9.4.1 - Task 1
- ✅ Installation at ~/opt/gradle - Task 3
- ✅ Cache at ~/.gradle (default, no changes needed)
- ✅ PATH configuration - Task 4
- ✅ GitHub workflow build_args support (现有逻辑已支持任意 ARG，无需修改)

**Placeholder scan:** No TBDs, no placeholders, all code shown.

**Type consistency:** GRADLE_VERSION used consistently across ARG, ENV, and installation URL.