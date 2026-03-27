# ==========================================
# 0. 定义全局构建参数 (可动态指定 JDK 版本，默认设为 8)
# ==========================================
ARG JDK_VERSION=8

# 使用 Eclipse Temurin 官方 JDK 镜像 (基于坚如磐石的 Ubuntu 22.04 Jammy)
FROM eclipse-temurin:${JDK_VERSION}-jdk-jammy

# 设置环境变量，防止 apt 交互式安装卡住
ENV DEBIAN_FRONTEND=noninteractive
# --- 新增：设置时区环境变量 ---
ENV TZ=Asia/Shanghai

# ==========================================
# 1. 集中管理所有核心工具的版本号 (按需修改)
# ==========================================
ENV MAVEN_VERSION=3.9.9
ENV NODE_VERSION=20.18.0
ENV PYTHON_VERSION=3.11
ENV UV_VERSION=0.5.21
ENV PNPM_VERSION=9.12.3
ENV YARN_VERSION=1.22.22
ENV NEOVIM_VERSION=0.11.6
ENV CHEZMOI_VERSION=2.70.0

# 配置全局 PATH，确保所有手动安装的二进制文件随时可用
ENV PATH="/root/.local/bin:/opt/maven/bin:/opt/nvim-linux-x86_64/bin:${PATH}"

# ==========================================
# 2. 安装系统基础工具、配置时区及 Python
# ==========================================
RUN apt-get update && \
    # --- 修改：安装 tzdata 并立即配置时区 ---
    apt-get install -y --no-install-recommends tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # 安装基础依赖
    apt-get install -y --no-install-recommends \
        software-properties-common curl wget git unzip sudo ca-certificates \
        build-essential jq ripgrep sqlite3 \
        zsh tmux && \
    # 引入 deadsnakes PPA 安装 Python
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev && \
    # 将指定 Python 版本设为系统默认
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
    # 安装 pip
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# 3. 精确安装指定版本的 Maven
# ==========================================
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar xzf /tmp/maven.tar.gz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven && \
    rm /tmp/maven.tar.gz

# ==========================================
# 4. 精确安装指定版本的 Node.js, pnpm 和 yarn
# ==========================================
RUN wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -O /tmp/nodejs.tar.xz && \
    tar -xJf /tmp/nodejs.tar.xz -C /usr/local --strip-components=1 && \
    rm /tmp/nodejs.tar.xz && \
    npm install -g pnpm@${PNPM_VERSION} yarn@${YARN_VERSION}

# ==========================================
# 5. 精确安装指定版本的 uv (极速 Python 包管理器)
# ==========================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_VERSION=${UV_VERSION} sh

# ==========================================
# 6. 精确安装现代版 Neovim (官方预编译二进制包)
# ==========================================
RUN wget https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C /opt && \
    rm /tmp/nvim.tar.gz

# ==========================================
# 7. 精确安装指定版本的 chezmoi (dotfiles 管理工具)
# ==========================================
RUN wget https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz -O /tmp/chezmoi.tar.gz && \
    tar -xzf /tmp/chezmoi.tar.gz -C /usr/local/bin chezmoi && \
    rm /tmp/chezmoi.tar.gz

# ==========================================
# 8. 安装 Claude Code
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash

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

ENV SHELL=/bin/zsh
WORKDIR /app
CMD ["sleep", "infinity"]
