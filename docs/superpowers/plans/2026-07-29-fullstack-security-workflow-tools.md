# Fullstack 镜像增加 gitleaks / betterleaks / pre-commit 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 fullstack 开发镜像中内置固定版本的 gitleaks、betterleaks（安全扫描）和 pre-commit（git hook 框架），均带 sha256 校验。

**Architecture:** 沿用 Dockerfile 现有"一工具一 RUN 块、ARG/ENV 锁版本、neo 用户装进 `~/.local/bin`"的模式。gitleaks/betterleaks 从 GitHub Releases 下载 tar 包（保留上游原名存入 /tmp），`grep "<asset>" <checksums> | (cd /tmp && sha256sum -c -)` 校验后仅解压二进制成员；pre-commit 无二进制发行版，经镜像已有的 uv 以 `uv tool install` 装入独立 venv。三个新块插在 16.8（zoxide）之后、16.9（Rust）之前。

**Tech Stack:** Dockerfile（Ubuntu noble 基础）、wget、GNU coreutils（sha256sum）、tar、uv 0.5.21。

## Global Constraints

- **不进行本地 docker 构建测试**（仓库 CLAUDE.md 硬性规定）；验证依赖构建期冒烟命令、sha256 校验与 CI 构建。
- 仅 amd64：下载资产固定为 `linux_x64`，与镜像内其他工具一致。
- 版本固定且可 build-arg 覆盖：`GITLEAKS_VERSION=8.30.1`、`BETTERLEAKS_VERSION=1.7.2`、`PRE_COMMIT_VERSION=4.6.1`。
- 所有工具装入 neo 用户 `~/.local/bin`（已在全局 PATH）。
- gitleaks/betterleaks 必须做 sha256 校验：`grep "<asset>" <checksums> | (cd /tmp && sha256sum -c -)`（下载保留上游资产原名存入 /tmp；清单记录相对文件名，须在子 shell 内 cd 到 /tmp 校验）。
- RUN 块编号固定为 16.8.1 / 16.8.2 / 16.8.3，插入于 16.8（zoxide）与 16.9（Rust）之间。
- 只 commit 不 push（仓库约定：推送由用户自行执行；push 到 main 且触碰 `fullstack-image/**` 会自动触发 `build-fullstack.yml` 重建镜像）。

---

## File Structure

- Modify: `fullstack-image/fullstack.Dockerfile` — 新增 3 组 ARG/ENV 版本声明 + 3 个安装 RUN 块（16.8.1/16.8.2/16.8.3）
- Modify: `CLAUDE.md` — 更新镜像清单中 `fullstack-image/` 行的说明
- Commit（已生成，尚未入库）: `docs/superpowers/specs/2026-07-29-fullstack-security-workflow-tools-design.md`、`docs/superpowers/plans/2026-07-29-fullstack-security-workflow-tools.md`

---

### Task 1: 安装 gitleaks 8.30.1（ARG/ENV + RUN 块 16.8.1）

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`（ARG 声明块、ENV 赋值区、16.8 与 16.9 之间）

**Interfaces:**
- Consumes: 无
- Produces: `ARG GITLEAKS_VERSION=8.30.1` 行与 `    gitleaks version` 行——Task 2 的 Edit 锚点依赖这两处文本已存在

- [ ] **Step 1: 插入 ARG 声明**

对 `fullstack-image/fullstack.Dockerfile` 执行 Edit：

old_string:
```
ARG ZOXIDE_VERSION=0.9.9
ARG RUST_VERSION=1.97.1
```

new_string:
```
ARG ZOXIDE_VERSION=0.9.9
ARG GITLEAKS_VERSION=8.30.1
ARG RUST_VERSION=1.97.1
```

- [ ] **Step 2: 插入 ENV 赋值**

old_string:
```
ENV ZOXIDE_VERSION=${ZOXIDE_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

new_string:
```
ENV ZOXIDE_VERSION=${ZOXIDE_VERSION}
ENV GITLEAKS_VERSION=${GITLEAKS_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

- [ ] **Step 3: 插入 RUN 块 16.8.1**

old_string:
```
    rm /tmp/zoxide.tar.gz

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

new_string:
```
    rm /tmp/zoxide.tar.gz

# ==========================================
# 16.8.1. 精确安装指定版本的 gitleaks (neo 用户)
# ==========================================
RUN wget https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz -O /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz && \
    wget https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt -O /tmp/gitleaks_checksums.txt && \
    grep "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" /tmp/gitleaks_checksums.txt | (cd /tmp && sha256sum -c -) && \
    tar -xzf /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz -C ~/.local/bin gitleaks && \
    rm /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz /tmp/gitleaks_checksums.txt && \
    gitleaks version

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

- [ ] **Step 4: 验证版本声明与引用数量**

Run:
```bash
cd /home/neo/work/personal/self-docker-build-image
grep -c "GITLEAKS_VERSION" fullstack-image/fullstack.Dockerfile
```
Expected: 输出 `7`（ARG 1 行 + ENV 1 行 + RUN 内 5 行引用：tar 包下载、校验单下载、grep 校验、tar 解压、rm 清理）

- [ ] **Step 5: 验证 RUN 块 shell 语法**

Run:
```bash
sed -n '/^RUN wget https:\/\/github.com\/gitleaks/,/^    gitleaks version$/p' fullstack-image/fullstack.Dockerfile | sed 's/^RUN //' | bash -n && echo "RUN body shell syntax OK"
```
Expected: 输出 `RUN body shell syntax OK`（无语法错误输出）

- [ ] **Step 6: 验证 checksums 行可唯一匹配**

Run:
```bash
curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt | grep -c "gitleaks_8.30.1_linux_x64.tar.gz"
```
Expected: 输出 `1`（grep 管道恰好校验一行）

- [ ] **Step 7: 提交**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add pinned gitleaks 8.30.1 with sha256 verification"
```

---

### Task 2: 安装 betterleaks 1.7.2（ARG/ENV + RUN 块 16.8.2）

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`（同 Task 1 三处区域）

**Interfaces:**
- Consumes: Task 1 产出的 `ARG GITLEAKS_VERSION=8.30.1`、`ENV GITLEAKS_VERSION=...`、`    gitleaks version` 行（作为 Edit 锚点）
- Produces: `ARG BETTERLEAKS_VERSION=1.7.2` 行与 `    betterleaks version` 行——Task 3 的 Edit 锚点依赖这两处文本

- [ ] **Step 1: 插入 ARG 声明**

old_string:
```
ARG GITLEAKS_VERSION=8.30.1
ARG RUST_VERSION=1.97.1
```

new_string:
```
ARG GITLEAKS_VERSION=8.30.1
ARG BETTERLEAKS_VERSION=1.7.2
ARG RUST_VERSION=1.97.1
```

- [ ] **Step 2: 插入 ENV 赋值**

old_string:
```
ENV GITLEAKS_VERSION=${GITLEAKS_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

new_string:
```
ENV GITLEAKS_VERSION=${GITLEAKS_VERSION}
ENV BETTERLEAKS_VERSION=${BETTERLEAKS_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

- [ ] **Step 3: 插入 RUN 块 16.8.2**

注意：上游 checksum 文件名为通用的 `checksums.txt`，需另存为 `/tmp/betterleaks_checksums.txt`。

old_string:
```
    gitleaks version

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

new_string:
```
    gitleaks version

# ==========================================
# 16.8.2. 精确安装指定版本的 betterleaks (neo 用户)
# ==========================================
RUN wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -O /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz && \
    wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/checksums.txt -O /tmp/betterleaks_checksums.txt && \
    grep "betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz" /tmp/betterleaks_checksums.txt | (cd /tmp && sha256sum -c -) && \
    tar -xzf /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -C ~/.local/bin betterleaks && \
    rm /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz /tmp/betterleaks_checksums.txt && \
    betterleaks version

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

- [ ] **Step 4: 验证版本声明与引用数量**

Run:
```bash
cd /home/neo/work/personal/self-docker-build-image
grep -c "BETTERLEAKS_VERSION" fullstack-image/fullstack.Dockerfile
```
Expected: 输出 `7`（ARG 1 行 + ENV 1 行 + RUN 内 5 行引用）

- [ ] **Step 5: 验证 RUN 块 shell 语法**

Run:
```bash
sed -n '/^RUN wget https:\/\/github.com\/betterleaks/,/^    betterleaks version$/p' fullstack-image/fullstack.Dockerfile | sed 's/^RUN //' | bash -n && echo "RUN body shell syntax OK"
```
Expected: 输出 `RUN body shell syntax OK`

- [ ] **Step 6: 验证 checksums 行可唯一匹配**

Run:
```bash
curl -fsSL https://github.com/betterleaks/betterleaks/releases/download/v1.7.2/checksums.txt | grep -c "betterleaks_1.7.2_linux_x64.tar.gz"
```
Expected: 输出 `1`

- [ ] **Step 7: 提交**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add pinned betterleaks 1.7.2 with sha256 verification"
```

---

### Task 3: 安装 pre-commit 4.6.1（ARG/ENV + RUN 块 16.8.3，经 uv tool）

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`（同前三处区域）

**Interfaces:**
- Consumes: Task 2 产出的 `ARG BETTERLEAKS_VERSION=1.7.2`、`ENV BETTERLEAKS_VERSION=...`、`    betterleaks version` 行（Edit 锚点）；块 14 已安装的 uv（`~/.local/bin/uv`，运行时依赖）
- Produces: `pre-commit` 二进制落入 `~/.local/bin`（构建期），无后续任务依赖其产出

- [ ] **Step 1: 插入 ARG 声明**

old_string:
```
ARG BETTERLEAKS_VERSION=1.7.2
ARG RUST_VERSION=1.97.1
```

new_string:
```
ARG BETTERLEAKS_VERSION=1.7.2
ARG PRE_COMMIT_VERSION=4.6.1
ARG RUST_VERSION=1.97.1
```

- [ ] **Step 2: 插入 ENV 赋值**

old_string:
```
ENV BETTERLEAKS_VERSION=${BETTERLEAKS_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

new_string:
```
ENV BETTERLEAKS_VERSION=${BETTERLEAKS_VERSION}
ENV PRE_COMMIT_VERSION=${PRE_COMMIT_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
```

- [ ] **Step 3: 插入 RUN 块 16.8.3**

old_string:
```
    betterleaks version

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

new_string:
```
    betterleaks version

# ==========================================
# 16.8.3. 精确安装指定版本的 pre-commit (neo 用户, 经 uv tool)
# ==========================================
RUN ~/.local/bin/uv tool install pre-commit==${PRE_COMMIT_VERSION} && \
    pre-commit --version

# ==========================================
# 16.9. 精确安装指定版本的 Rust 工具链 (neo 用户)
```

- [ ] **Step 4: 验证版本声明与引用数量**

Run:
```bash
cd /home/neo/work/personal/self-docker-build-image
grep -c "PRE_COMMIT_VERSION" fullstack-image/fullstack.Dockerfile
```
Expected: 输出 `3`（ARG 1 行 + ENV 1 行 + RUN 内 1 处引用）

- [ ] **Step 5: 验证 RUN 块 shell 语法**

Run:
```bash
sed -n '/^RUN ~\/\.local\/bin\/uv tool install/,/^    pre-commit --version$/p' fullstack-image/fullstack.Dockerfile | sed 's/^RUN //' | bash -n && echo "RUN body shell syntax OK"
```
Expected: 输出 `RUN body shell syntax OK`

- [ ] **Step 6: 提交**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat(fullstack): add pinned pre-commit 4.6.1 via uv tool"
```

---

### Task 4: 更新 CLAUDE.md 镜像清单 + 设计/计划文档入库 + 最终核对

**Files:**
- Modify: `CLAUDE.md`（镜像清单表格中 `fullstack-image/` 行）
- Commit: `docs/superpowers/specs/2026-07-29-fullstack-security-workflow-tools-design.md`、`docs/superpowers/plans/2026-07-29-fullstack-security-workflow-tools.md`

**Interfaces:**
- Consumes: Task 1–3 完成后的 Dockerfile（最终核对读取三个 16.8.x 块）
- Produces: 无

- [ ] **Step 1: 更新镜像清单说明**

对 `CLAUDE.md` 执行 Edit：

old_string:
```
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装) + Rust/Tauri 编译环境 (固定版本), Git via PPA |
```

new_string:
```
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装) + Rust/Tauri 编译环境 (固定版本), Git via PPA, 内置安全扫描 (gitleaks + betterleaks) 与 pre-commit |
```

- [ ] **Step 2: 最终核对——块顺序正确**

Run:
```bash
cd /home/neo/work/personal/self-docker-build-image
grep -n "^# 16\.8\." fullstack-image/fullstack.Dockerfile
```
Expected: 恰好 3 行，按 `16.8.1`（gitleaks）、`16.8.2`（betterleaks）、`16.8.3`（pre-commit）顺序排列，且行号均小于 16.9 块所在行

- [ ] **Step 3: 最终核对——变更范围最小**

Run:
```bash
git -C /home/neo/work/personal/self-docker-build-image status --porcelain
```
Expected: 仅 ` M CLAUDE.md` 与两个未跟踪的 docs 文件（`?? docs/superpowers/specs/...`、`?? docs/superpowers/plans/...`）；`fullstack-image/fullstack.Dockerfile` 不应再出现（已在 Task 1–3 分别提交）

- [ ] **Step 4: 提交文档与清单更新**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-07-29-fullstack-security-workflow-tools-design.md docs/superpowers/plans/2026-07-29-fullstack-security-workflow-tools.md
git commit -m "docs: fullstack 镜像清单补充 gitleaks/betterleaks/pre-commit，入库设计文档与实施计划"
```

- [ ] **Step 5: 告知用户后续动作（不执行）**

向用户说明：4 个 commit 已就绪，未 push；用户自行 push 到 main 后，`fullstack-image/**` 路径变更会自动触发 `build-fullstack.yml` 重建并推送 `ghcr.io/{owner}/fullstack:latest`，构建期三个冒烟命令（`gitleaks version` / `betterleaks version` / `pre-commit --version`）与 sha256 校验构成最终验证。
