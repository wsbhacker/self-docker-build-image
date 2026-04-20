# Claude Code 版本控制实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Claude Code 安装添加版本控制能力，支持 latest/stable/精确版本号。

**Architecture:** 在 Dockerfile 中添加 ARG 和 ENV 变量，修改 install.sh 调用命令传递版本参数。

**Tech Stack:** Dockerfile 构建参数机制

---

## 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `fullstack-image/fullstack.Dockerfile` | 修改 | 添加 CLAUDE_VERSION ARG/ENV，修改安装命令 |

---

### Task 1: 修改 Dockerfile

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`

- [ ] **Step 1: 在全局 ARG 区域添加 CLAUDE_VERSION**

在第 5 行 `ARG PYTHON_VERSION=3.12` 后添加：

```dockerfile
ARG CLAUDE_VERSION=latest
```

- [ ] **Step 2: 在 FROM 后 ARG 区域重新声明 CLAUDE_VERSION**

在第 18 行 `ARG UV_VERSION=0.5.21` 后添加：

```dockerfile
ARG CLAUDE_VERSION=latest
```

- [ ] **Step 3: 在 ENV 区域添加 CLAUDE_VERSION 环境变量**

在第 43 行 `ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}` 后添加：

```dockerfile
ENV CLAUDE_VERSION=${CLAUDE_VERSION}
```

- [ ] **Step 4: 修改 Claude Code 安装命令**

将第 148 行：

```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash
```

改为：

```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION}
```

- [ ] **Step 5: 提交变更**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat: add CLAUDE_VERSION build arg for version control"
```

---

## 完成标准

Dockerfile 支持通过 `--build-arg CLAUDE_VERSION=<version>` 指定 Claude Code 安装版本。