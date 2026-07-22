# Fullstack 镜像 Rust 开发环境设计文档

- **日期**: 2026-07-22
- **状态**: 已批准
- **范围**: `fullstack-image/fullstack.Dockerfile`、`CLAUDE.md`
- **关联镜像**: `ghcr.io/{owner}/fullstack`（全部 5 个场景 tag：android / web.24 / yzj / p / yzj.web）

## 1. 背景与目标

### 1.1 现状

`fullstack.Dockerfile` **未安装任何 Rust 工具链**（无 rustup/cargo/rustc）。镜像中仅有以 Rust 编写的预编译静态二进制（ripgrep、fd、fzf、zoxide，均为 musl 预编译产物），与开发环境无关。

### 1.2 目标

在构建时将锁定版本的 Rust 开发环境**无条件烘焙**进所有场景镜像，满足：

1. 通用 Rust 开发（CLI/后端）：`cargo build/test`、clippy、rustfmt
2. 完整 IDE/分析支持：rust-src、rust-analyzer
3. Tauri v2 桌面项目的**编译与打包**（系统链接库就位）

### 1.3 非目标

- 交叉编译 target（wasm32、musl 等）——日后按需 `rustup target add`
- Rust 版本自动更新——升级靠手动改 ARG 重建（与仓库其他固定版本工具一致）
- arm64 支持——该镜像仅构建 `linux/amd64`（`build-fullstack.yml` 已限定）
- 烘焙 tauri-cli——官方推荐项目级 `@tauri-apps/cli`（npm devDependency），使用时安装
- 预烘焙 AppImage 打包工具（linuxdeploy）——运行时网络直连无障碍，首次打包自动下载

## 2. 决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| 安装时机 | 构建时无条件烘焙 | 所有场景开箱即用，用户明确接受体积代价 |
| 安装方式 | 方案 A：固定版本 rustup-init 二进制 | 与仓库"所有工具固定版本下载"模式一致，构建完全可复现 |
| 版本策略 | 固定具体版本（ARG） | 构建可复现；可通过 workflow `build_args` 临时覆盖 |
| 安装组件 | `--profile default` + rust-src + rust-analyzer | 满足 IDE 支持且避免 complete profile 的 miri/rustc-dev/llvm-tools（数百 MB） |
| 目录布局 | 默认 `~/.rustup` + `~/.cargo` | rustup/cargo 均不原生支持 XDG（[#247](https://github.com/rust-lang/rustup/issues/247)、[#13928](https://github.com/rust-lang/cargo/issues/13928)）；默认路径与全部文档/教程一致 |
| Tauri 系统依赖 | 烘焙进镜像（apt） | 编译期链接库，缺失则 `cargo build` 直接失败；保证"编译必成功"的核心需求 |
| tauri-cli | 不烘焙 | 主流用法是项目 npm devDependency，使用时安装 |
| linuxdeploy（AppImage 打包） | 不烘焙 | 运行时直连无障碍，首次 `tauri build` 自动下载至 `~/.cache/tauri`（约 20MB） |

### 2.1 方案比较（安装方式）

- **方案 A（采用）**：从官方版本归档 `static.rust-lang.org/rustup/archive/<version>/` 下载固定版本 rustup-init 二进制，执行 `--default-toolchain <版本> --profile default` 安装。优点：rustup 本体与工具链双锁版本、构建可复现、全功能 rustup、与仓库模式一致；缺点：多一个 ARG。
- **方案 B**：官方 `sh.rustup.rs` 一行脚本 + `--default-toolchain <版本>`。优点：最标准简洁；缺点：rustup 本体不锁版本（2025 年 1.28.0 曾出现破坏性发布 [rustup#4211](https://github.com/rust-lang/rustup/issues/4211)），配合本仓库每 4 小时的自动重建机制存在无人值守构建失败的小概率风险。
- **方案 C**：多阶段 `COPY --from=rust:<版本>-slim`。优点：构建期不依赖外部下载；缺点：官方镜像工具链为 root 所有的系统目录布局，需 chown/改 ENV 才能让 neo 用户正常 `rustup update/install`；slim 不含 rust-src/rust-analyzer 仍需联网补装；偏离仓库模式最远。
- **方案 D**：`apt-get install rustc cargo`。Ubuntu 24.04 仓库 rustc 约 1.75（落后一年半以上，不支持 edition 2024），违反"过时技术不能使用"规范，**明确否决**。

A 与 B 对"编译/build 成功"的最终效果完全相同（编译由工具链 rustc/cargo 完成，rustup 仅是安装器）；差异仅在构建链的可复现性。

## 3. 详细设计

### 3.1 版本与下载地址（均已验证 HTTP 200，2026-07-22）

| 组件 | 版本 | 地址 |
|---|---|---|
| rustup-init | 1.29.0（2026-03-05 发布） | `https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init` |
| Rust 工具链 | 1.97.1（2026-07-16 发布，当前 stable） | 由 rustup 从 `static.rust-lang.org` 自动拉取（`channel-rust-1.97.1.toml` 已验证存在） |
| Tauri 系统依赖 | 随 Ubuntu 24.04（noble）仓库 | apt（webkit2gtk 为 **4.1**，Tauri v2 所需版本） |

### 3.2 Dockerfile 改动（5 处）

以下改动均位于 `fullstack-image/fullstack.Dockerfile`。

**a) ARG 声明**——在 FROM 之后的 ARG 区块（约 19–42 行，与 `MAVEN_VERSION` 等同风格）新增：

```dockerfile
ARG RUST_VERSION=1.97.1
ARG RUSTUP_VERSION=1.29.0
```

> 不在 FROM 之前的全局 ARG 区块声明（与 `MAVEN_VERSION`/`NODE_VERSION` 等大多数工具一致；workflow 的 `build_args` 传入 `RUST_VERSION=x` 可正常覆盖）。

**b) ENV 设置**——在版本类 ENV 区块（约 52–81 行，如 `ENV ZOXIDE_VERSION` 附近）新增：

```dockerfile
ENV RUST_VERSION=${RUST_VERSION}
ENV RUSTUP_VERSION=${RUSTUP_VERSION}
```

**c) PATH 追加**——修改约 84 行的全局 PATH，**最前面**加入 cargo bin 目录：

```dockerfile
ENV PATH="/home/${USERNAME}/.cargo/bin:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

**d) 新章节「2.5. 安装 Tauri 桌面开发系统依赖」**——插入在第 2 节 apt 区块（约 107 行）之后、Python multi-stage COPY（约 110 行）之前。此处 USER 仍为 root（`USER ${USERNAME}` 直到约 140 行才切换），**无需** USER 切换语句：

```dockerfile
# ==========================================
# 2.5. 安装 Tauri 桌面开发系统依赖 (root)
# webkit2gtk-4.1 为 Ubuntu 24.04 提供的版本，Tauri v2 所需
# ==========================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pkg-config file libssl-dev libxdo-dev \
        libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

依赖包说明：`build-essential`/`curl`/`wget` 已在第 2 节安装；`libsoup-3.0-dev`/`libjavascriptcoregtk-4.1-dev` 由 `libwebkit2gtk-4.1-dev` 间接依赖自动带入。

**e) 新章节「16.9. 精确安装指定版本的 Rust 工具链」**——插入在 16.8 节 zoxide（约 226 行）之后、17 节 OpenSpec（约 228 行）之前。此处 USER 为 neo：

```dockerfile
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
```

参数说明：
- `-y`：非交互安装（CI 构建要求）
- `--no-modify-path`：PATH 已由 Dockerfile 全局 ENV 统一设置（且镜像使用 ZDOTDIR 托管 zsh 配置，不应被安装器改写 rc 文件）
- `--default-toolchain ${RUST_VERSION}`：构建时即装好并设为默认工具链，容器运行后 `cargo` 零网络依赖直接可用（若用 `none`，首次 `cargo build` 会现场下载数百 MB，容器无网即失败）

### 3.3 CLAUDE.md 更新

镜像清单表格中 fullstack 行说明改为：

```
全栈开发环境 + Android SDK (运行时安装) + Rust/Tauri 编译环境 (固定版本), Git via PPA
```

### 3.4 无需改动的文件

| 文件 | 原因 |
|---|---|
| `fullstack-image/entrypoint.sh` | rustup 状态在镜像层，启动无需处理（不同于 Android SDK 的运行时安装） |
| `fullstack-image/scenarios.yaml` | Rust 无条件包含于全部 5 个场景，无需新增场景 |
| `.github/workflows/build-fullstack.yml` | 平台仍 `linux/amd64`；现有 `build_args` 机制天然支持 `RUST_VERSION=x;RUSTUP_VERSION=y` 临时覆盖 |
| `.github/workflows/check-fullstack-updates.yml` | Rust/rustup 版本不纳入自动检测，升级靠手动改 ARG（与 Maven/Node 等固定版本工具一致） |

## 4. 影响

- **镜像体积**：每个场景 tag **+约 1.0~1.3GB**（工具链 ~700MB + rust-src/rust-analyzer ~250MB + Tauri apt 依赖 ~300MB）
- **构建时间**：+约 1~2 分钟（rustup 下载工具链）
- **GHCR 存储**：5 个 tag 合计约 +5~6.5GB（层缓存可部分缓解）
- **向后兼容**：纯新增，不改动任何现有工具的安装方式与路径

## 5. 验证方案

遵循仓库约定（CLAUDE.md："不进行本地测试"），验证在 CI 与发布后的容器内完成：

1. **CI 构建**：push 到 main 或手动 dispatch → `build-fullstack.yml` / `build-fullstack-batch.yml` 全场景构建成功
2. **容器内冒烟检查**（镜像发布后）：
   ```bash
   rustc --version          # 期望 rustc 1.97.1
   cargo --version          # 期望 cargo 1.97.1
   rustup --version         # 期望 rustup 1.29.0
   rustup show              # 默认工具链 = 1.97.1-x86_64-unknown-linux-gnu
   rustup component list --installed   # 含 rust-src、rust-analyzer、clippy、rustfmt
   which cargo              # 期望 /home/neo/.cargo/bin/cargo
   ```
3. **编译冒烟**：
   ```bash
   cargo new /tmp/hello && cd /tmp/hello && cargo build && ./target/debug/hello
   ```
4. **Tauri 编译链接验证**（可选，在真实 Tauri 项目中）：新建 Tauri 项目执行 `cargo build`，确认 `webkit2gtk-4.1` pkg-config 探测通过、无链接错误

## 6. 使用指南

### 6.1 Rust 版本切换（三个层级）

| 层级 | 方式 | 适用场景 | 持久性 |
|---|---|---|---|
| 镜像默认 | 改 Dockerfile `ARG RUST_VERSION` 重建，或 dispatch 时传 `build_args: RUST_VERSION=x` | 长期全局使用某版本 | 跟随镜像，跨一切重启/重建 |
| 项目级 | 项目根目录 `rust-toolchain.toml`（`channel = "1.90.0"`） | 单个项目锁定版本 | 文件随项目走；首次使用需联网自动下载对应工具链 |
| 运行时 | `rustup toolchain install x && rustup default x`、`cargo +x build`、`rustup override set x` | 临时切换 | 存在容器可写层：`docker restart` 保留；容器重建后丢失（除非 home 挂卷） |

优先级：`RUSTUP_TOOLCHAIN` 环境变量 > 项目 `rust-toolchain.toml` > 目录 override > 全局默认。

### 6.2 挂载推荐

关键原理：**bind mount 会遮盖镜像内容**（空目录挂到 `~/.cargo/bin` 会使 shim 消失而破坏环境）；**named volume 首次启动（卷为空时）自动复制镜像内容**，但镜像升级后不再同步。

| 目录 | 推荐 | 方式 |
|---|---|---|
| `~/work`（项目代码） | ✅ 必须 | bind / named volume |
| `~/.cargo/registry`（crate 缓存） | ✅ 强烈推荐 | bind 或 named volume（不在镜像中，遮盖无害） |
| `~/.cargo/git`（git 依赖缓存） | ✅ 推荐 | 同上 |
| `~/.cache/tauri`（AppImage 打包工具缓存） | ✅ 推荐 | bind 或 named volume（首次打包下载后持久化） |
| 项目 `target/` | ⭕ 可选 | named volume（Mac/Win bind 慢） |
| `~/.rustup/toolchains` | ⚠️ 仅 named volume | bind 遮盖会丢失镜像默认工具链 |
| `~/.rustup` + `~/.cargo` 整体 | ⚠️ 仅 named volume | 完全持久化；代价：镜像升级的烘焙工具不再生效 |
| `~/.cargo/bin` | ❌ 不要挂载 | 含镜像烘焙的 shim，遮盖即破坏 |
| `~/.rustup/settings.toml` | ❌ 不要单独挂载 | 须与 toolchains/ 同步 |
| `~/.cargo/credentials.toml` | ⭕ 按需单文件只读 bind | crates.io 令牌，避免烘焙进镜像 |
| 整个 `/home/neo` | ❌ 不推荐 | 所有镜像工具都在 home 下，整体遮盖使镜像升级失去意义 |

### 6.3 Tauri 工作流

1. **CLI**：项目前端安装 `@tauri-apps/cli`（devDependency），使用 `pnpm tauri dev` / `pnpm tauri build`（官方推荐方式，不依赖全局 cargo-tauri）
2. **编译**：系统链接库已烘焙，`cargo build` 直接就绪
3. **AppImage 打包**：首次 `tauri build` 自动下载 linuxdeploy 至 `~/.cache/tauri`（约 20MB，运行时直连无障碍）；挂载该目录可跨容器持久化。可用 `TAURI_TOOLS_PATH` 环境变量覆盖缓存位置
4. **仅打 deb 包**（跳过 AppImage 下载）：`pnpm tauri build --bundles deb`

## 7. 参考资料

- rustup 安装与版本归档：https://rustup.rs/ 、https://rust-lang.github.io/rustup/installation/other.html
- rustup profiles（minimal/default/complete）：https://rust-lang.github.io/rustup/concepts/profiles.html
- rustup XDG 追踪 issue：https://github.com/rust-lang/rustup/issues/247
- cargo XDG 现状：https://github.com/rust-lang/cargo/issues/13928
- Tauri v2 Prerequisites（Ubuntu 依赖清单）：https://v2.tauri.app/start/prerequisites/
- Tauri AppImage 打包与工具缓存：https://v2.tauri.app/distribute/appimage/ 、https://github.com/tauri-apps/tauri/issues/15106
- Rust 发布节奏与版本：https://blog.rust-lang.org/releases/latest/ 、https://releases.rs/
- rustup 1.29.0 changelog：https://github.com/rust-lang/rustup/blob/main/CHANGELOG.md
