# self-docker-build-image

自定义 Docker 镜像构建配置集合，用于构建并推送各种服务的 Docker 镜像到 GitHub Container Registry (ghcr.io)。
请注意！！！不进行本地测试

## 镜像清单

| 目录 | 镜像名称 | 说明 |
|------|---------|------|
| `anki/` | `ghcr.io/{owner}/ankis` | Anki 同步服务器 (Python) |
| `frp/` | `ghcr.io/{owner}/frpc`, `ghcr.io/{owner}/frps` | FRP 客户端和服务端 |
| `litellm-pgvector/` | `ghcr.io/{owner}/litellm-pgvector` | LiteLLM 与 PGVector 支持 |
| `text-embeddings-inference/` | (手动构建) | 文本嵌入推理，支持 CUDA Blackwell (Rust) |
| `fish-speech/` | `ghcr.io/{owner}/fish-speech-webui`, `ghcr.io/{owner}/fish-speech-server` | Fish Speech TTS (从上游仓库构建) |
| `cosyvoice/` | `ghcr.io/{owner}/cosyvoice` | CosyVoice TTS，支持 CUDA Blackwell (从上游仓库构建) |
| `fullstack-image/` | `ghcr.io/{owner}/fullstack` | 全栈开发环境 + Android SDK (运行时安装), Git via PPA |
| `glm-coding-grabber/` | `ghcr.io/{owner}/glm-coding-grabber` | GLM Coding CAPTCHA 识别服务 (从上游仓库构建) |
| `open-web-search/` | `ghcr.io/{owner}/open-web-search` | Open WebSearch MCP 服务器 (从上游仓库构建, 手动维护 Dockerfile) |
| `pg-ocs-sync-worker/` | `ghcr.io/{owner}/pg-ddl-sync` | PostgreSQL DDL 同步伴生服务 (Python) |


## CI/CD 工作流

### 触发方式

1. **手动触发** (`workflow_dispatch`)
   - 在 GitHub Actions 页面手动运行
   - 可指定 `version_tag` 参数 (如 `v1.0.0` 或 `latest`)

2. **自动触发** (`push`)
   - 当对应目录下的文件变更时自动触发
   - 默认打 `latest` 标签

### 工作流文件

- `.github/workflows/build-anki.yml` - Anki 同步服务器
- `.github/workflows/build-frpc.yml` - FRP 客户端
- `.github/workflows/build-frps.yml` - FRP 服务端
- `.github/workflows/build-litellm-pgvector.yml` - LiteLLM PGVector
- `.github/workflows/build-fish-speech.yml` - Fish Speech (webui + server)
- `.github/workflows/build-cosyvoice.yml` - CosyVoice TTS
- `.github/workflows/build-glm-coding-grabber.yml` - GLM Coding CAPTCHA 识别服务
- `.github/workflows/build-open-web-search.yml` - Open WebSearch MCP 服务器
- `.github/workflows/build-pg-ddl-sync.yml` - PostgreSQL DDL 同步伴生服务

### 工作流模式

```yaml
# 典型工作流结构
on:
  workflow_dispatch:
    inputs:
      version_tag:
        description: "设定镜像 Tag"
        default: "latest"
  push:
    branches: [main]
    paths:
      - "<directory>/**"
      - ".github/workflows/build-<name>.yml"

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v6
      - uses: docker/login-action@v3
      - uses: docker/setup-qemu-action@v4      # 多架构支持
      - uses: docker/setup-buildx-action@v4    # Buildx
      - uses: docker/metadata-action@v6        # 标签生成
      - uses: docker/build-push-action@v7      # 构建推送
        with:
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## 架构模式

### 多架构构建
- 使用 `docker/setup-qemu-action` 和 `docker/setup-buildx-action`
- 支持 `linux/amd64` 和 `linux/arm64`
- 部分镜像仅支持 `linux/amd64` (如 CUDA 相关)

### 构建缓存
- 使用 GitHub Actions 缓存 (`type=gha`)
- `cache-from: type=gha` - 读取缓存
- `cache-to: type=gha,mode=max` - 写入最大缓存

### 安全措施
- **Pre-commit hooks**: 使用 `gitleaks` 检测密钥泄露
- **Dependabot**: 每周自动更新 GitHub Actions 版本
- **权限最小化**: 仅请求 `contents:read` 和 `packages:write`

## 添加新镜像

1. 创建目录和 Dockerfile: `<name>/<Name>.Dockerfile`
2. 创建工作流: `.github/workflows/build-<name>.yml`
3. 参考 `build-anki.yml` 作为模板
4. 更新本文件的镜像清单
