# Fullstack 镜像增加 gitleaks / betterleaks / pre-commit 设计文档

- 日期: 2026-07-29
- 状态: 待实施
- 影响文件: `fullstack-image/fullstack.Dockerfile`, `CLAUDE.md`

## 1. 背景与目标

fullstack 开发镜像目前没有密钥扫描与 git hook 管理工具。本仓库自身的 pre-commit 配置已使用 gitleaks hook，但容器内缺少可直接调用的 `gitleaks` / `pre-commit` 二进制，开发者在容器内无法直接运行扫描或 `pre-commit run`。

目标: 在 fullstack 镜像中内置三个开发工作流工具:

| 工具 | 版本 | 用途 |
|------|------|------|
| gitleaks | 8.30.1 | 密钥泄露扫描（与仓库 pre-commit hook 一致） |
| betterleaks | 1.7.2 | gitleaks 同作者的继任扫描器（检出率更高，命令/配置兼容 gitleaks） |
| pre-commit | 4.6.1 | git hook 框架，统一管理 gitleaks 等钩子 |

## 2. 关键决策

| 决策点 | 结论 | 理由 |
|--------|------|------|
| gitleaks vs betterleaks | 两个都装 | gitleaks 已 feature-complete（仅安全补丁）但仍稳定、与现有 pre-commit 配置一致；betterleaks 是活跃继任者（检出召回率 70%→98.6%），CLI 与 `.gitleaks.toml` 兼容。双装便于对比与过渡 |
| 下载校验 | 做 sha256 校验 | 两个上游均提供 checksums 文件；安全类工具本身防篡改有意义（与仓库内其他工具的现有写法不同，属有意升级） |
| 版本管理 | `ARG`/`ENV` 固定版本，可 build-arg 覆盖 | 与 ripgrep/fd/fzf/zoxide 等现有工具完全一致 |
| 安装位置 | neo 用户 `~/.local/bin` | 已在全局 PATH 中，与现有用户态工具一致 |
| Dockerfile 结构 | 每工具一个独立 RUN 块（16.8.1 / 16.8.2 / 16.8.3） | 与现有"一工具一块"约定一致，层缓存相互独立，单独升级/移除不影响其他工具 |
| pre-commit 安装方式 | `uv tool install pre-commit==${PRE_COMMIT_VERSION}` | pre-commit 无二进制发行版；镜像已内置 uv 0.5.21；uv tool 提供独立 venv，二进制落在 `~/.local/bin`，不污染用户 site-packages（优于 `pip install --user`；无需为它单独引入 pipx） |
| 架构 | 仅 amd64（`linux_x64`） | 镜像内所有现有二进制均为硬编码 x86_64，保持一致 |

已否决的替代方案:
- **合并为单个 RUN 块**: 层缓存耦合，偏离现有约定。
- **`COPY --from=ghcr.io/...` 官方镜像**: 需手工维护 digest 防篡改，betterleaks 镜像内二进制路径不明，与全文件 wget 模式割裂。
- **将工具版本纳入 `check-fullstack-updates.yml`**: 该工作流仅监控 claude-code / codex 发布触发整体重建，不管理逐工具版本；其他固定版本工具（rg/fd 等）同样靠手工修改 Dockerfile 升级，保持一致。

## 3. 变更详情

### 3.1 `fullstack.Dockerfile` — 版本声明

在 FROM 之后的 ARG 声明块（与 `RIPGREP_VERSION` 等同处，约 33 行 `ZOXIDE_VERSION` 附近）追加:

```dockerfile
ARG GITLEAKS_VERSION=8.30.1
ARG BETTERLEAKS_VERSION=1.7.2
ARG PRE_COMMIT_VERSION=4.6.1
```

在 ENV 赋值区（与 `ENV RIPGREP_VERSION=${RIPGREP_VERSION}` 等同处）追加:

```dockerfile
ENV GITLEAKS_VERSION=${GITLEAKS_VERSION}
ENV BETTERLEAKS_VERSION=${BETTERLEAKS_VERSION}
ENV PRE_COMMIT_VERSION=${PRE_COMMIT_VERSION}
```

### 3.2 `fullstack.Dockerfile` — 安装块

插入位置: 16.8（zoxide）之后、16.9（Rust 工具链）之前，均以 neo 用户执行。

**16.8.1 gitleaks**（已验证: checksums 行为标准 `<sha256>  <filename>` 格式；tar 包根目录含单一 `gitleaks` 二进制）:

```dockerfile
# ==========================================
# 16.8.1. 精确安装指定版本的 gitleaks (neo 用户)
# ==========================================
RUN wget https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz -O /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz && \
    wget https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt -O /tmp/gitleaks_checksums.txt && \
    grep "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" /tmp/gitleaks_checksums.txt | (cd /tmp && sha256sum -c -) && \
    tar -xzf /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz -C ~/.local/bin gitleaks && \
    rm /tmp/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz /tmp/gitleaks_checksums.txt && \
    gitleaks version
```

**16.8.2 betterleaks**（上游 checksum 文件名为通用的 `checksums.txt`，需另存为 `/tmp/betterleaks_checksums.txt`；tar 包根目录含单一 `betterleaks` 二进制）:

```dockerfile
# ==========================================
# 16.8.2. 精确安装指定版本的 betterleaks (neo 用户)
# ==========================================
RUN wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -O /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz && \
    wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/checksums.txt -O /tmp/betterleaks_checksums.txt && \
    grep "betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz" /tmp/betterleaks_checksums.txt | (cd /tmp && sha256sum -c -) && \
    tar -xzf /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -C ~/.local/bin betterleaks && \
    rm /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz /tmp/betterleaks_checksums.txt && \
    betterleaks version
```

**16.8.3 pre-commit**（须位于 block 14 uv 安装之后，此处天然满足）:

```dockerfile
# ==========================================
# 16.8.3. 精确安装指定版本的 pre-commit (neo 用户, 经 uv tool)
# ==========================================
RUN ~/.local/bin/uv tool install pre-commit==${PRE_COMMIT_VERSION} && \
    pre-commit --version
```

要点:
- 下载保留上游资产原名存入 `/tmp`；`grep "<asset>" | (cd /tmp && sha256sum -c -)` 在子 shell 内进入 `/tmp` 校验——`sha256sum -c` 按清单记录的相对文件名在 CWD 查找文件，而该 RUN 执行时 CWD 为 `/`（WORKDIR 在文件后部声明），不 cd 进 `/tmp` 必然 `No such file` 失败；grep 同时保证只校验本平台对应行，避免依赖 `--ignore-missing`。
- `tar -xzf ... -C ~/.local/bin <member>` 仅解压二进制成员，不把 LICENSE/README 带入 `~/.local/bin`。
- 每块末尾的 `X version` / `--version` 冒烟命令使二进制损坏时构建立即失败。
- `uv tool install` 默认将二进制放入 `~/.local/bin`（已在 PATH），venv 位于 `~/.local/share/uv/tools`。
- pre-commit 运行时依赖（git、python）镜像已具备；python 语言 hook 由 pre-commit 自建独立 venv。

### 3.3 `CLAUDE.md` — 镜像清单

更新 `fullstack-image/` 行的说明，例如:

> 全栈开发环境 + Android SDK (运行时安装) + Rust/Tauri 编译环境 (固定版本), Git via PPA, 内置安全扫描 (gitleaks + betterleaks) 与 pre-commit

### 3.4 不变更项

- `PATH`: `~/.local/bin` 已在全局 PATH。
- `.github/workflows/check-fullstack-updates.yml`: 不纳入逐工具版本监控（见决策表）。
- `entrypoint.sh` / zsh 补全: 不添加（YAGNI）。
- 构建工作流 `build-fullstack-batch.yml` 等: 无需修改，新工具随 Dockerfile 变更经 push 触发重建。

## 4. 验证

依据仓库约定**不进行本地 docker 构建测试**，验证依赖:

1. **构建期冒烟**: 三个 RUN 块末尾的 `gitleaks version` / `betterleaks version` / `pre-commit --version` 在二进制缺失或损坏时令构建失败。
2. **sha256 校验**: 构建期 `sha256sum -c` 拦截篡改或下载损坏。
3. **设计期已离线验证**（本机 x86_64 Linux）:
   - 两个 tar 包内部结构均为根目录单一二进制（另含 LICENSE/README）。
   - checksums 文件行格式为 `<sha256>  <asset-filename>`，`grep | sha256sum -c` 路径可行。
   - `gitleaks version` → `8.30.1`；`betterleaks version` → `1.7.2`。
   - 审查期更正（2026-07-30）：最初"/tmp 改名存放 + 直接 `sha256sum -c`"的校验链因文件名/CWD 错配必然 `No such file` 失败（已本地复现 exit=1）；定稿改为"保留上游原名 + `(cd /tmp && sha256sum -c -)`"，实测输出 `OK`、exit=0。
4. **CI 验证**: 变更 push 到 main 后由 GitHub Actions 构建 fullstack 镜像（amd64），构建成功即通过。

## 5. 工具活跃度确认（CLAUDE.md 技术选型规则）

- gitleaks: feature-complete 仅安全补丁——已与用户确认，保留（与现有 pre-commit 配置一致）。
- betterleaks: 2026-03 发布，活跃开发，Aikido 赞助，MIT——已确认。
- pre-commit: 活跃（v4.6.1, 2026-07-21 发布），无需确认。
