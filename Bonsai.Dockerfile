# Bonsai 2 (Ternary-Bonsai-2-27B, Qwen3.8-27B 底座, PQ2_0) 推理镜像
# 目标硬件: RTX 5070 Laptop 12GB (Blackwell, 驱动 CUDA 13.4) + 64GB 内存, 200K 上下文
# 模型不打进镜像: 运行时 volume 挂载到 /app/models/bonsai2-gguf/27B (见文件末尾)
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

# 两个版本锚点与上游强配套 (demo 脚本 <-> fork 二进制 release), 升级时必须一起动
ARG BONSAI_REPO_REF=17b143e
ARG LLAMA_TAG=prism-b10709-9a9394a

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 官方 demo 脚本 (start_llama_server.sh 等), pin 到提交; 上游一周 bump 数次, 不 pin 不可复现
RUN curl -fL "https://github.com/PrismML-Eng/Bonsai-demo/archive/${BONSAI_REPO_REF}.tar.gz" -o /tmp/bonsai.tar.gz \
    && tar -xzf /tmp/bonsai.tar.gz --strip-components=1 \
    && rm /tmp/bonsai.tar.gz \
    && chmod +x scripts/*.sh

# 直接烤入 PrismML fork 的 CUDA 12.8 预编译二进制, 不走 setup.sh:
#   1) docker build 期无 GPU, download_binaries.sh 探测只会选中 CPU 版
#   2) 5070 是 Blackwell (sm_120), CUDA 12.4 及以下的包无对应内核, 必须 12.8
#   3) 主线 llama.cpp 不含 PQ2_0 内核: 会拒绝加载或静默输出乱码
RUN curl -fL "https://github.com/PrismML-Eng/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-bin-linux-cuda-12.8-x64.tar.gz" -o /tmp/llama.tar.gz \
    && mkdir -p bin/cuda \
    && { tar -xzf /tmp/llama.tar.gz -C bin/cuda --strip-components=1 \
         || tar -xzf /tmp/llama.tar.gz -C bin/cuda; } \
    && echo "$LLAMA_TAG" > bin/cuda/.llama_release \
    && rm /tmp/llama.tar.gz

# 显式钉住家族/尺寸: 上游默认值本周刚从 ternary 翻成 bonsai2, 不赌默认
# KV/上下文策略针对 12GB 显存 + 64GB 内存:
#   BONSAI_CTX=204800        200K 上下文 (上限 262144, RAM 分层默认只给 64K)
#   BONSAI_MMPROJ_CPU=1      视觉投影器 (~0.63GB) 留系统内存
#   --no-kv-offload (ENTRY)  200K FP16 KV ~12.5GB 放不进显存, 留在内存; 权重全上 GPU (~9GB 显存)
ENV BONSAI_FAMILY=bonsai2 \
    BONSAI_MODEL=27B \
    BONSAI_HOST=0.0.0.0 \
    BONSAI_CTX=204800 \
    BONSAI_MMPROJ_CPU=1

ENTRYPOINT ["./scripts/start_llama_server.sh", "--no-kv-offload"]

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s \
    CMD curl -sf http://localhost:8080/health || exit 1

# ── 用法 ──
# 模型自备, 下载到宿主机 (公开仓库, 免 token):
#   uvx --from huggingface_hub hf download prism-ml/Ternary-Bonsai-2-27B-gguf \
#       Ternary-Bonsai-2-27B-PQ2_0.gguf Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
#       --local-dir ~/models/bonsai2-27B
#
# 构建并运行:
#   docker build -f Bonsai.Dockerfile -t bonsai:latest .
#   docker run --gpus all -p 8080:8080 \
#       -v ~/models/bonsai2-27B:/app/models/bonsai2-gguf/27B bonsai:latest
#
# 首次启动后访问 http://localhost:8080 ; 若 fork 二进制不接受 --no-kv-offload
# (llama-server --help 可查), 退路是去掉该参数并改用 BONSAI_NGL 部分卸载
