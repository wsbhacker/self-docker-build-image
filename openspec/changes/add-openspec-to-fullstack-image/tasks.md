## 1. ARG 和 ENV 配置

- [ ] 1.1 在 ARG 区域（line 10-19）添加 `ARG OPENSPEC_VERSION=1.2.0`
- [ ] 1.2 在 ENV 区域（line 29-38）添加 `ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}`

## 2. 安装步骤

- [ ] 2.1 在 Claude Code 安装步骤前后添加 `RUN ~/.local/node/bin/npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}`