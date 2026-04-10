## Why

为 fullstack Docker 镜像添加 OpenSpec 工具安装，使开发者能够使用规范驱动开发 (SDD) 工作流与 AI 编程助手协作。OpenSpec 是专为 AI 编程助手设计的轻量级规范管理工具，可减少 AI 幻觉、提高开发效率。版本需要可配置，以便后续升级或降级。

## What Changes

- 在 Dockerfile 中添加 OpenSpec 安装步骤
- 新增 `OPENSPEC_VERSION` ARG 参数，默认值 `1.2.0`
- 使用 npm 全局安装 `@fission-ai/openspec@${OPENSPEC_VERSION}`
- 版本管理模式与其他工具（Maven、Node、Neovim 等）保持一致

## Capabilities

### New Capabilities

- `openspec-install`: 添加 OpenSpec 工具安装能力，版本可通过 ARG 参数配置

### Modified Capabilities

无现有 spec 需要修改。

## Impact

- **文件修改**: `fullstack-image/fullstack.Dockerfile`
- **新增 ARG**: `OPENSPEC_VERSION=1.2.0`（约 line 10-19 区域）
- **新增 ENV**: `OPENSPEC_VERSION=${OPENSPEC_VERSION}`（约 line 29-38 区域）
- **新增 RUN**: npm install 步骤（约 line 139 前后，与 Claude Code 安装位置相近）
- **依赖**: 需要 Node.js 已安装（现有 line 110-114 已满足）