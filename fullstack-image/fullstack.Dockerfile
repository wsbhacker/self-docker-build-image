# ==========================================
# 0. 定义全局构建参数 (可动态指定各软件版本)
# ==========================================
ARG JDK_VERSION=8
ARG PYTHON_VERSION=3.12
ARG CLAUDE_VERSION=latest
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
ARG GIT_VERSION=latest
ARG IMAGE_TAG=default
ARG BUILD_TIMESTAMP=default

# ===== Python multi-stage =====
FROM python:${PYTHON_VERSION}-slim AS python

# 使用 Eclipse Temurin 官方 JDK 镜像 (基于 Ubuntu 24 noble)
FROM eclipse-temurin:${JDK_VERSION}-jdk-noble

# 在 FROM 后重新声明 ARG 以接收外部 build-arg
ARG MAVEN_VERSION=3.9.9
ARG GRADLE_VERSION=9.4.1
ARG NODE_VERSION=24.18.0
ARG PYTHON_VERSION=3.12
ARG UV_VERSION=0.5.21
ARG CLAUDE_VERSION=latest
ARG PNPM_VERSION=9.12.3
ARG YARN_VERSION=1.22.22
ARG NEOVIM_VERSION=0.11.6
ARG CHEZMOI_VERSION=2.70.0
ARG OPENSPEC_VERSION=1.2.0
ARG RIPGREP_VERSION=15.1.0
ARG FD_VERSION=10.4.2
ARG FZF_VERSION=0.72.0
ARG ZOXIDE_VERSION=0.9.9
ARG GITLEAKS_VERSION=8.30.1
ARG BETTERLEAKS_VERSION=1.7.2
ARG PRE_COMMIT_VERSION=4.6.1
ARG RUST_VERSION=1.97.1
ARG RUSTUP_VERSION=1.29.0
ARG GO_VERSION=1.26.5
ARG GO_SHA256=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=neo
ARG TARGET_PLATFORM=android-35
ARG BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
ARG GIT_VERSION=latest
ARG IMAGE_TAG=default
ARG BUILD_TIMESTAMP=default

# 设置环境变量，防止 apt 交互式安装卡住
ENV DEBIAN_FRONTEND=noninteractive
# --- 新增：设置时区环境变量 ---
ENV TZ=Asia/Shanghai

# ==========================================
# 1. 将构建参数转为环境变量 (供后续使用)
# ==========================================
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV GRADLE_VERSION=${GRADLE_VERSION}
ENV NODE_VERSION=${NODE_VERSION}
ENV PYTHON_VERSION=${PYTHON_VERSION}
ENV UV_VERSION=${UV_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}
ENV YARN_VERSION=${YARN_VERSION}
ENV NEOVIM_VERSION=${NEOVIM_VERSION}
ENV CHEZMOI_VERSION=${CHEZMOI_VERSION}
ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}
ENV CLAUDE_VERSION=${CLAUDE_VERSION}
ENV RIPGREP_VERSION=${RIPGREP_VERSION}
ENV FD_VERSION=${FD_VERSION}
ENV FZF_VERSION=${FZF_VERSION}
ENV ZOXIDE_VERSION=${ZOXIDE_VERSION}
ENV GITLEAKS_VERSION=${GITLEAKS_VERSION}
ENV BETTERLEAKS_VERSION=${BETTERLEAKS_VERSION}
ENV PRE_COMMIT_VERSION=${PRE_COMMIT_VERSION}
ENV RUST_VERSION=${RUST_VERSION}
ENV RUSTUP_VERSION=${RUSTUP_VERSION}
ENV GO_VERSION=${GO_VERSION}
ENV GOROOT=/home/${USERNAME}/opt/go
ENV GOPATH=/home/${USERNAME}/go
ENV USER_UID=${USER_UID}
ENV USER_GID=${USER_GID}
ENV USERNAME=${USERNAME}
ENV ZDOTDIR=/home/${USERNAME}/zsh
ENV HOME=/home/${USERNAME}
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION}
ENV GIT_VERSION=${GIT_VERSION}
ENV TARGET_PLATFORM=${TARGET_PLATFORM}
ENV BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION}
ENV IMAGE_TAG=${IMAGE_TAG}
ENV BUILD_TIMESTAMP=${BUILD_TIMESTAMP}
ENV CTAG=${IMAGE_TAG}
ENV CID=${IMAGE_TAG}:${BUILD_TIMESTAMP}


# 防止 Tauri (WebKitGTK) 硬件加速在 WSL2 下闪烁或黑屏
ENV WEBKIT_DISABLE_COMPOSITING_MODE=1
# 支持 Chrome 及 Chromium 免沙箱运行
ENV CHROME_FLAGS="--no-sandbox --disable-dev-shm-usage"
ENV CHROMIUM_FLAGS="--no-sandbox --disable-dev-shm-usage"


# 配置全局 PATH，确保所有手动安装的二进制文件随时可用
ENV PATH="/home/${USERNAME}/opt/go/bin:/home/${USERNAME}/go/bin:/home/${USERNAME}/.cargo/bin:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# ==========================================
# 2. 安装系统基础工具、配置时区及 Python
# ==========================================
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
        build-essential jq sqlite3 netcat-openbsd \
        zsh tmux && \
    # 清理 PPA 引导依赖（software-properties-common 及其自动安装的依赖）
    apt-get remove -y software-properties-common && \
    apt-get autoremove -y && \
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# 2.5. 安装 Tauri、Electron (ZCode) 及 GUI 认证环境 (root)
# 彻底解决 Ubuntu 24.04 Snap 依赖与 t64 包名问题
# ==========================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # --- 1. Tauri 构建核心依赖 ---
        pkg-config file libssl-dev libxdo-dev \
        libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev \
        # --- 2. GUI/D-Bus 系统总线与 MESA 图形渲染 ---
        dbus dbus-x11 libgl1-mesa-dri libglx-mesa0 libgles2 \
        fonts-noto-cjk fonts-noto-color-emoji \
        # --- 3. Chromium / Electron 核心底座依赖 ---
        libgbm1 libnss3 libasound2t64 libsecret-1-0 \
        libx11-xcb1 libxcb-dri3-0 libxshmfence1 \
        xdg-utils && \
    # --- 4. 安装 Google Chrome 替代被 Snap 化的 chromium (支持 OAuth 认证唤起) ---
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb && \
    apt-get install -y --no-install-recommends /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*



# ===== Python multi-stage copy =====
COPY --from=python /usr/local /usr/local

# ==========================================
# 8. 创建 neo 用户（非 root）并配置 sudo
# id被占用就删除原来的,不存在就创建
# ==========================================
RUN set -eux; \
    existing_user=$(getent passwd ${USER_UID} | cut -d: -f1 || true); \
    existing_group=$(getent group ${USER_GID} | cut -d: -f1 || true); \
    \
    if [ -n "$existing_user" ]; then \
        userdel -r "$existing_user" || true; \
    fi; \
    \
    if [ -n "$existing_group" ]; then \
        groupdel "$existing_group" || true; \
    fi; \
    \
    # 清理可能被 root 创建的 /home/neo 目录，确保 useradd -m 干净创建; \
    rm -rf /home/${USERNAME}; \
    \
    groupadd -g ${USER_GID} ${USERNAME}; \
    useradd -m -s /bin/zsh -u ${USER_UID} -g ${USER_GID} ${USERNAME}; \
    \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# ==========================================
# 9. 切换到 neo 用户
# ==========================================
USER ${USERNAME}

# ==========================================
# 10. 创建 neo 目录结构
# ==========================================
RUN mkdir -p ~/.local/bin ~/.local/share ~/opt ~/work

# ==========================================
# 11. 创建 Android SDK 目录
# ==========================================
USER root
RUN mkdir -p ${ANDROID_HOME} && \
    chown -R ${USERNAME}:${USERNAME} ${ANDROID_HOME}
USER ${USERNAME}

# ==========================================
# 12. 精确安装指定版本的 Maven (neo 用户)
# ==========================================
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar xzf /tmp/maven.tar.gz -C ~/opt && \
    ln -s ~/opt/apache-maven-${MAVEN_VERSION} ~/opt/maven && \
    rm /tmp/maven.tar.gz

# ==========================================
# 12.5. 精确安装指定版本的 Gradle (neo 用户)
# ==========================================
RUN wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -O /tmp/gradle.zip && \
    unzip /tmp/gradle.zip -d ~/opt && \
    mv ~/opt/gradle-${GRADLE_VERSION} ~/opt/gradle && \
    rm /tmp/gradle.zip

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
# 16.5. 精确安装指定版本的 ripgrep (neo 用户)
# ==========================================
RUN wget https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz -O /tmp/ripgrep.tar.gz && \
    tar -xzf /tmp/ripgrep.tar.gz -C ~/.local/bin --strip-components=1 ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg && \
    rm /tmp/ripgrep.tar.gz

# ==========================================
# 16.6. 精确安装指定版本的 fd (neo 用户)
# ==========================================
RUN wget https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz -O /tmp/fd.tar.gz && \
    tar -xzf /tmp/fd.tar.gz -C ~/.local/bin --strip-components=1 fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd && \
    rm /tmp/fd.tar.gz

# ==========================================
# 16.7. 精确安装指定版本的 fzf (neo 用户)
# ==========================================
RUN wget https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz -O /tmp/fzf.tar.gz && \
    tar -xzf /tmp/fzf.tar.gz -C ~/.local/bin && \
    rm /tmp/fzf.tar.gz

# ==========================================
# 16.8. 精确安装指定版本的 zoxide (neo 用户)
# ==========================================
RUN wget https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz -O /tmp/zoxide.tar.gz && \
    tar -xzf /tmp/zoxide.tar.gz -C ~/.local/bin zoxide && \
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
# 16.8.2. 精确安装指定版本的 betterleaks (neo 用户)
# ==========================================
RUN wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -O /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz && \
    wget https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/checksums.txt -O /tmp/betterleaks_checksums.txt && \
    grep "betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz" /tmp/betterleaks_checksums.txt | (cd /tmp && sha256sum -c -) && \
    tar -xzf /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz -C ~/.local/bin betterleaks && \
    rm /tmp/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz /tmp/betterleaks_checksums.txt && \
    betterleaks version

# ==========================================
# 16.8.3. 精确安装指定版本的 pre-commit (neo 用户, 经 uv tool)
# ==========================================
RUN ~/.local/bin/uv tool install pre-commit==${PRE_COMMIT_VERSION} && \
    pre-commit --version

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
# 16.10. 精确安装指定版本的 Go (neo 用户)
# 官方 tarball + 硬编码 sha256 校验 (带外信任锚: 同时防传输损坏与下载源篡改)
# 升级版本时重抓哈希:
#   curl -sSL "https://go.dev/dl/?mode=json" | jq -r '.[0].files[] | select(.os=="linux" and .arch=="amd64") | .sha256'
# tarball 自带 go/ 目录, 解压后落在 ~/opt/go
# ==========================================
RUN wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/go.tar.gz -C ~/opt && \
    rm /tmp/go.tar.gz && \
    mkdir -p ~/go/bin && \
    ~/opt/go/bin/go version

# ==========================================
# 17. 为 neo 用户安装 OpenSpec
# ==========================================
RUN ~/.local/node/bin/npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}

# ==========================================
# 18. 为 neo 用户安装 Claude Code
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION}

# ==========================================
# 19. 为 neo 用户安装 Codex CLI
# ==========================================
ARG CODEX_VERSION=latest
ENV CODEX_RELEASE=${CODEX_VERSION}
ENV CODEX_NON_INTERACTIVE=true
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh

# ==========================================
# 20. 添加 entrypoint（处理 ZDOTDIR + Oh My Zsh）
# ==========================================
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER ${USERNAME}

WORKDIR /home/${USERNAME}/work
ENV SHELL=/bin/zsh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]
