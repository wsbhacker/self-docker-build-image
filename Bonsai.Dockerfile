FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# 安装官方 setup.sh 所需的依赖环境
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1. 克隆官方 Bonsai-demo 仓库
RUN git clone https://github.com/PrismML-Eng/Bonsai-demo.git .

# 2. 执行官方 setup.sh，自动抓取官方匹配好的 Release 二进制
# 声明跳过镜像内模型下载（用 volume 挂载）和跳过自带的 heavy openwebui 安装
ENV BONSAI_SKIP_GGUF=1
ENV BONSAI_OPENWEBUI=0
ENV BONSAI_CODE_INTERPRETER=0

RUN chmod +x setup.sh scripts/*.sh && ./setup.sh

# 暴露 llama-server 端口
EXPOSE 8080

# 以官方启动脚本为入口
ENTRYPOINT ["./scripts/start_llama_server.sh"]
