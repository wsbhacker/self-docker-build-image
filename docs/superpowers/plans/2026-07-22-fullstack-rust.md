# Fullstack Rust 开发环境 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 fullstack 镜像全部场景中烘焙锁定版本的 Rust 工具链（rustup 1.29.0 + Rust 1.97.1 + rust-src/rust-analyzer）与 Tauri v2 编译期系统依赖，并同步更新 CLAUDE.md。

**Architecture:** 在 `fullstack.Dockerfile` 中新增两个编号 RUN 章节，沿用仓库现有的固定版本下载模式：root 权限的 apt 章节 2.5 安装 Tauri 链接库；neo 用户章节 16.9 从官方版本归档下载锁定版本的 rustup-init 并安装锁定版本的工具链。版本经 ARG→ENV 传递（可被 workflow `build_args` 覆盖），`~/.cargo/bin` 前置加入全局 PATH。

**Tech Stack:** Docker (BuildKit, linux/amd64)、rustup/rustc/cargo、apt (Ubuntu 24.04 noble)、GitHub Actions。

## Global Constraints

- **不进行本地测试**（仓库 CLAUDE.md 明确约定）——不执行本地 `docker build`
- **不 push、不合并**——实施阶段仅做本地提交；推送、合并到 main 及其后的 CI 验证全部由用户自行完成
- 镜像仅构建 `linux/amd64`，所有下载 URL 使用 x86_64 资产
- 固定版本：`RUST_VERSION=1.97.1`、`RUSTUP_VERSION=1.29.0`，均以 ARG 声明 + ENV 导出
- 工具以非 root 用户 `neo` 安装；PATH 由 Dockerfile 全局 ENV 设置，rustup-init 必须带 `--no-modify-path`（镜像使用 ZDOTDIR 托管 zsh，禁止安装器改写 rc 文件）
- 使用 `--profile default` + `rustup component add rust-src rust-analyzer`，**不使用** complete profile（避免 miri/rustc-dev/llvm-tools 等数百 MB 组件）
- 所有 apt 安装使用 `--no-install-recommends`，并以 `apt-get clean && rm -rf /var/lib/apt/lists/*` 收尾
- **不**烘焙 tauri-cli（项目级 npm devDependency 为官方推荐用法）；**不**预烘焙 linuxdeploy（运行时直连无障碍）
- 当前工作分支：`add-rust-dev-env`（已含设计文档提交 `f7ebbc4`）

## File Structure

| 文件 | 操作 | 责任 |
|---|---|---|
| `fullstack-image/fullstack.Dockerfile` | Modify | 4 处编辑（ARG 区块、ENV 区块、PATH、新章节 16.9）+ 1 处编辑（新章节 2.5） |
| `CLAUDE.md` | Modify | 镜像清单表格 fullstack 行说明 |

章节插入使用**内容锚点**（非行号）：Task 1 的 16.9 插在 zoxide 章节之后，Task 2 的 2.5 插在第 2 节 apt 清理行与 Python COPY 注释之间，两处编辑互不重叠，顺序无关。

---

### Task 1: 烘焙 Rust 工具链（ARG/ENV/PATH + 章节 16.9）

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`（ARG 区块、ENV 区块、PATH 行、zoxide 章节之后）

**Interfaces:**
- Consumes: 无（首个实现任务）
- Produces: 镜像内 `rustc`/`cargo`/`rustup` 可用（`/home/neo/.cargo/bin/`）、`ENV RUST_VERSION`/`ENV RUSTUP_VERSION` 可在运行时查询——Task 4 的冒烟检查依赖这些

- [ ] **Step 1: 在 ARG 区块追加版本参数**

在 `fullstack-image/fullstack.Dockerfile` 中定位（FROM 之后的 ARG 区块，`ARG ZOXIDE_VERSION` 与 `ARG USER_UID` 之间），将：

```dockerfile
ARG ZOXIDE_VERSION=0.9.9
ARG USER_UID=1000
```

替换为：

```dockerfile
ARG ZOXIDE_VERSION=0.9.9
ARG RUST_VERSION=1.97.1
ARG RUSTUP_VERSION=1.29.0
ARG USER_UID=1000
```

- [ ] **Step 2: 在 ENV 区块导出版本变量**

定位版本类 ENV 区块（`ENV ZOXIDE_VERSION` 与 `ENV USER_UID` 之间），将：

```dockerfile
ENV ZOXIDE_VERSION=${ZOXIDE_VERSION}
ENV USER_UID=${USER_UID}
```

替换为：

```dockerfile
ENV ZOXIDE_VERSION=${ZOXIDE_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
ENV RUSTUP_VERSION=${RUSTUP_VERSION}
ENV USER_UID=${USER_UID}
```

- [ ] **Step 3: PATH 前置 cargo bin 目录**

定位全局 PATH 行（以 `ENV PATH="/home/${USERNAME}/.local/bin:` 开头），将：

```dockerfile
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

替换为：

```dockerfile
ENV PATH="/home/${USERNAME}/.cargo/bin:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

- [ ] **Step 4: 在 zoxide 章节之后插入 16.9 Rust 工具链章节**

定位 16.8 zoxide 章节结尾与 17 节 OpenSpec 注释之间，将：

```dockerfile
RUN wget https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz -O /tmp/zoxide.tar.gz && \
    tar -xzf /tmp/zoxide.tar.gz -C ~/.local/bin zoxide && \
    rm /tmp/zoxide.tar.gz

# ==========================================
# 17. 为 neo 用户安装 OpenSpec
# ==========================================
```

替换为：

```dockerfile
RUN wget https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz -O /tmp/zoxide.tar.gz && \
    tar -xzf /tmp/zoxide.tar.gz -C ~/.local/bin zoxide && \
    rm /tmp/zoxide.tar.gz

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
# rustup 本体与 Rust 工具链双锁版本
# rustup-init 来自官方版本归档 (static.rust-lang.org/rustup/archive/)
# default profile (rustc/cargo/rust-std/rustfmt/clippy/rust-docs) + rust-src + rust-analyzer
# 不使用 complete profile，避免 miri/rustc-dev/llvm-tools 等数百 MB 编译器内部组件
# ==========================================
RUN curl -fsSL https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init -o /tmp/rustup-init && \
    chmod +x /tmp/rustup-init && \
    /tmp/rustup-init -y \
        --no-modify-path \
        --profile default \
        --default-toolchain ${RUST_VERSION} && \
    rm /tmp/rustup-init && \
    ~/.cargo/bin/rustup component add rust-src rust-analyzer

# ==========================================
# 17. 为 neo 用户安装 OpenSpec
# ==========================================
```

- [ ] **Step 5: 静态验证编辑结果**

Run:
```bash
grep -n "ARG RUST_VERSION=1.97.1" fullstack-image/fullstack.Dockerfile
grep -n "ARG RUSTUP_VERSION=1.29.0" fullstack-image/fullstack.Dockerfile
grep -n "ENV RUST_VERSION=\${RUST_VERSION}" fullstack-image/fullstack.Dockerfile
grep -n "ENV RUSTUP_VERSION=\${RUSTUP_VERSION}" fullstack-image/fullstack.Dockerfile
grep -n 'ENV PATH="/home/${USERNAME}/.cargo/bin:' fullstack-image/fullstack.Dockerfile
grep -n "rustup/archive/\${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" fullstack-image/fullstack.Dockerfile
grep -n "rustup component add rust-src rust-analyzer" fullstack-image/fullstack.Dockerfile
```
Expected: 每条命令恰好输出 1 行匹配（行号非空）。

- [ ] **Step 6: 确认下载源可达**

Run:
```bash
curl -sfI https://static.rust-lang.org/rustup/archive/1.29.0/x86_64-unknown-linux-gnu/rustup-init | head -1
```
Expected: `HTTP/2 200`（或 `HTTP/1.1 200`）。若失败则停止——URL 错误会导致 CI 构建失败。

- [ ] **Step 7: 复查 diff**

Run:
```bash
git diff fullstack-image/fullstack.Dockerfile
```
Expected: 仅包含上述 4 处编辑（2 行 ARG、2 行 ENV、PATH 前置 `.cargo/bin`、新增 16.9 章节），无其他改动。

- [ ] **Step 8: Commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "$(cat <<'EOF'
feat(fullstack): bake pinned Rust toolchain (rustup 1.29.0 + Rust 1.97.1)

rustup 本体与工具链双锁版本：rustup-init 来自官方版本归档，
default profile + rust-src/rust-analyzer 提供完整 IDE 支持。

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 烘焙 Tauri v2 编译期系统依赖（章节 2.5）

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`（第 2 节 apt 清理行与 Python multi-stage COPY 注释之间）

**Interfaces:**
- Consumes: Task 1 完成后的 Dockerfile（两任务编辑区域不重叠，锚点为内容匹配，顺序无依赖）
- Produces: `libwebkit2gtk-4.1-dev` 等链接库就位——Task 4 冒烟检查中的 `pkg-config --modversion webkit2gtk-4.1` 依赖此任务

说明：插入位置位于 `USER ${USERNAME}`（约 140 行）之前，当前 USER 为 root，**无需** USER 切换语句。

- [ ] **Step 1: 在第 2 节 apt 区块之后插入 2.5 章节**

在 `fullstack-image/fullstack.Dockerfile` 中定位第 2 节结尾与 Python COPY 注释之间，将：

```dockerfile
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ===== Python multi-stage copy =====
```

替换为：

```dockerfile
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# 2.5. 安装 Tauri 桌面开发系统依赖 (root)
# webkit2gtk-4.1 为 Ubuntu 24.04 提供的版本，Tauri v2 所需
# ==========================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pkg-config file libssl-dev libxdo-dev \
        libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ===== Python multi-stage copy =====
```

- [ ] **Step 2: 静态验证编辑结果**

Run:
```bash
grep -n "libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev" fullstack-image/fullstack.Dockerfile
grep -n "# 2.5. 安装 Tauri 桌面开发系统依赖 (root)" fullstack-image/fullstack.Dockerfile
```
Expected: 每条命令恰好输出 1 行匹配。

- [ ] **Step 3: 验证章节顺序正确（2.5 必须在 USER 切换之前）**

Run:
```bash
grep -n -e "# 2.5. 安装 Tauri" -e "^USER \${USERNAME}" fullstack-image/fullstack.Dockerfile | head -4
```
Expected: `# 2.5. 安装 Tauri...` 的行号 **小于** 首个 `USER ${USERNAME}` 的行号（即 2.5 在 root 上下文中执行）。

- [ ] **Step 4: 复查 diff 并 Commit**

```bash
git diff fullstack-image/fullstack.Dockerfile
```
Expected: 仅新增 2.5 章节（11 行），无其他改动。

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "$(cat <<'EOF'
feat(fullstack): add Tauri v2 compile-time system dependencies

libwebkit2gtk-4.1-dev 等链接库烘焙进镜像，保证 Tauri 项目
cargo build 在任何新容器中开箱即成功。

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 更新 CLAUDE.md 镜像清单

**Files:**
- Modify: `CLAUDE.md`（镜像清单表格 fullstack 行）

**Interfaces:**
- Consumes: Task 1、Task 2 的产出（描述依赖两者都已实现）
- Produces: 仓库文档与实际镜像内容一致

- [ ] **Step 1: 更新镜像清单表格行**

在 `CLAUDE.md` 的「镜像清单」表格中，将：

```markdown
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装), Git via PPA |
```

替换为：

```markdown
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装) + Rust/Tauri 编译环境 (固定版本), Git via PPA |
```

- [ ] **Step 2: 静态验证**

Run:
```bash
grep -n "Rust/Tauri 编译环境 (固定版本)" CLAUDE.md
```
Expected: 恰好 1 行匹配，位于镜像清单表格内。

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: note Rust/Tauri compile environment in fullstack image entry

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## 实施完成说明

Task 1–3 全部完成即实施结束。分支 `add-rust-dev-env` 本地应有 5 个提交（spec + plan + Rust 工具链 + Tauri 依赖 + CLAUDE.md）。

完成后向用户报告："实施完成，5 个提交已在本地分支 `add-rust-dev-env`，等待您自行 push/合并与验证。"

**禁止执行的动作**：`git push`、合并到 main、监控 CI、拉取镜像冒烟检查、触发批量重建——发布与验证全部由用户自行完成并人肉反馈。用户反馈构建失败或环境异常时，再根据反馈定位修复（冒烟检查命令参考设计文档 §5：`rustc --version`、`rustup component list --installed`、`cargo new && cargo build` 等）。
