# ==========================================
# 0. 定义全局构建参数 (可动态指定 JDK 版本，默认设为 8)
# ==========================================
ARG JDK_VERSION=8

# 使用 Eclipse Temurin 官方 JDK 镜像 (基于坚如磐石的 Ubuntu 22.04 Jammy)
FROM eclipse-temurin:${JDK_VERSION}-jdk-jammy

# 设置环境变量，防止 apt 交互式安装卡住
ENV DEBIAN_FRONTEND=noninteractive

# ==========================================
# 1. 集中管理所有核心工具的版本号 (按需修改)
# ==========================================
ENV MAVEN_VERSION=3.9.9
ENV NODE_VERSION=20.18.0
ENV PYTHON_VERSION=3.11
ENV UV_VERSION=0.5.21
ENV PNPM_VERSION=9.12.3
ENV YARN_VERSION=1.22.22
ENV NEOVIM_VERSION=0.10.4

# 配置全局 PATH，确保所有手动安装的二进制文件随时可用
ENV PATH="/root/.local/bin:/opt/maven/bin:/opt/nvim-linux64/bin:${PATH}"

# ==========================================
# 2. 安装系统基础工具和 Python 3.11 环境
# ==========================================
RUN apt-get update && \
    # 安装基础依赖、编译工具链(供插件原生扩展使用)、以及终端工具
    apt-get install -y --no-install-recommends \
        software-properties-common curl wget git unzip sudo ca-certificates \
        build-essential jq ripgrep sqlite3 \
        zsh tmux && \
    # 引入 deadsnakes PPA 以精准安装指定版本的 Python
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev && \
    # 将指定 Python 版本设为系统默认的 python3
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
    # 安装 pip
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    # 清理缓存，缩减镜像体积
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
    # 直接解压到 /usr/local，使其融入全局环境变量
    tar -xJf /tmp/nodejs.tar.xz -C /usr/local --strip-components=1 && \
    rm /tmp/nodejs.tar.xz && \
    # 安装前端主流包管理器
    npm install -g pnpm@${PNPM_VERSION} yarn@${YARN_VERSION}

# ==========================================
# 5. 精确安装指定版本的 uv (极速 Python 包管理器)
# ==========================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_VERSION=${UV_VERSION} sh

# ==========================================
# 6. 精确安装现代版 Neovim (官方预编译二进制包)
# ==========================================
RUN wget https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C /opt && \
    rm /tmp/nvim.tar.gz

# ==========================================
# 7. 安装 Claude Code (Native Install)
# 注：官方强烈建议保持最新版以对接云端 API，故不锁版本
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash

# ==========================================
# 8. 配置神级终端体验 (Zsh + Oh My Zsh + Tmux)
# ==========================================
# 无交互安装 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    # 下载自动补全和语法高亮插件
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    # 启用插件，并将主题修改为带有 Git 分支提示的 'ys' 主题
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' ~/.zshrc && \
    # 添加别名：输入 vim 或 vi 自动打开现代化 Neovim
    echo "alias vim='nvim'" >> ~/.zshrc && \
    echo "alias vi='nvim'" >> ~/.zshrc

# 设置默认 Shell 为 Zsh
ENV SHELL=/bin/zsh

# 设置工作目录
WORKDIR /app

# 启动容器时直接进入 Zsh 终端
CMD ["zsh"]
