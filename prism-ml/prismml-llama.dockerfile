# Bonsai 家族通用推理镜像: bonsai2 / ternary / bonsai(1-bit) × 27B/8B/4B/1.7B
# 镜像只含运行环境(CUDA 12.8 fork 二进制 + demo 脚本), 不含模型、不带任何模型偏好;
# 跑哪个家族/尺寸、上下文与 KV 策略, 由部署方声明(compose environment 或 docker run -e,
# 启动参数经 ENTRYPOINT 透传给 llama-server)
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
#   2) Blackwell (sm_120) 需要 CUDA 12.8 包, 12.4 及以下无对应内核
#   3) 主线 llama.cpp 不含 fork 内核: 会拒绝加载或静默输出乱码
#   同一份二进制读全家族: PQ2_0(bonsai2) / Q2_0(ternary) / Q1_0(bonsai)
RUN curl -fL "https://github.com/PrismML-Eng/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-bin-linux-cuda-12.8-x64.tar.gz" -o /tmp/llama.tar.gz \
    && mkdir -p bin/cuda \
    && { tar -xzf /tmp/llama.tar.gz -C bin/cuda --strip-components=1 \
         || tar -xzf /tmp/llama.tar.gz -C bin/cuda; } \
    && echo "$LLAMA_TAG" > bin/cuda/.llama_release \
    && rm /tmp/llama.tar.gz

# 镜像只留与模型无关的默认; 模型路由与调优留给部署方:
#   BONSAI_FAMILY / BONSAI_MODEL  模型路由(目录+文件匹配+采样+上下文分层); 不设=脚本默认 bonsai2/27B
#   BONSAI_CTX                    不设=按 RAM 自动分层; 27B 上限 262144, 老尺寸 65536
#   BONSAI_MMPROJ_CPU=1           视觉投影器留内存(小显存机器用)
#   启动参数追加 --no-kv-offload   KV 留内存(长上下文小显存); 不加=KV 随层上 GPU
ENV BONSAI_HOST=0.0.0.0

ENTRYPOINT ["./scripts/start_llama_server.sh"]

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s \
    CMD curl -sf http://localhost:8080/health || exit 1

# ── 用法(以 bonsai2 27B @12GB 显存 200K 为例; 其他家族/尺寸改 -e 与挂载路径) ──
# 模型自备(公开仓库, 免 token):
#   uvx --from huggingface_hub hf download prism-ml/Ternary-Bonsai-2-27B-gguf \
#       Ternary-Bonsai-2-27B-PQ2_0.gguf Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
#       --local-dir ~/models/bonsai2-27B
#
# 推荐用同目录 bonsai-2-27b.compose.yaml; 裸 docker run 等价形式:
#   docker run --gpus all -p 8080:8080 \
#       -e BONSAI_CTX=204800 -e BONSAI_MMPROJ_CPU=1 \
#       -v ~/models/bonsai2-27B:/app/models/bonsai2-gguf/27B \
#       ghcr.io/0xw5b/prismml-llama:latest --no-kv-offload
