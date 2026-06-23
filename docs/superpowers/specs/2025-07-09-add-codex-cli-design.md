# Add Codex CLI to fullstack-image

## Context

fullstack-image 已包含 Claude Code（AI coding agent）。需要添加 OpenAI Codex CLI 作为另一个 AI coding agent，保持一致的安装风格。

## Design

在 `fullstack-image/fullstack.Dockerfile` 第 236 行（Claude Code 安装之后）插入：

```dockerfile
# Codex CLI (OpenAI)
ARG CODEX_VERSION=latest
ENV CODEX_RELEASE=${CODEX_VERSION}
ENV CODEX_NON_INTERACTIVE=true
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

### 要点

- 使用官方安装脚本，与 Claude Code 的 `curl | bash` 风格一致
- `CODEX_VERSION` ARG 支持版本锁定，通过 CI workflow_dispatch 覆盖
- `CODEX_NON_INTERACTIVE=true` 跳过安装提示
- 官方脚本自动处理 amd64/arm64 多架构

## Files

- `fullstack-image/fullstack.Dockerfile` — 唯一修改文件
