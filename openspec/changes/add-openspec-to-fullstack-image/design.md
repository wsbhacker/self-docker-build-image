## Context

当前 fullstack Dockerfile 已有完善的版本管理模式：每个工具通过 ARG 定义默认版本，ENV 设置环境变量，安装步骤引用版本变量。现有工具包括 Maven、Node.js、Python、Neovim、chezmoi、Claude Code 等。OpenSpec 是 npm 包，依赖 Node.js，安装方式与 pnpm/yarn 相似。

## Goals / Non-Goals

**Goals:**
- 添加 OpenSpec 安装，版本可通过 ARG 参数配置
- 保持与现有工具版本管理模式一致
- 安装后 `openspec` 命令全局可用

**Non-Goals:**
- 不执行 `openspec init`（用户自行决定何时初始化项目）
- 不修改其他工具的安装方式

## Decisions

### 决策 1：安装位置

**选择**: 在 Claude Code 安装前后添加独立 RUN 步骤

**理由**:
- 遵循现有每个工具独立版本管理模式
- 与 Claude Code 同属 AI 开发工具类，位置相近
- 不合并到 pnpm/yarn 安装步骤，保持清晰分离

**备选方案**:
- 合并到 Node.js 安装步骤 → 打破独立版本管理模式

### 决策 2：安装命令

**选择**: `npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}`

**理由**:
- 与 pnpm/yarn 安装方式一致
- Node.js prefix 是 `~/.local/node`，`-g` 实际为用户级安装
- 命令自动安装到 PATH 中的 `~/.local/node/bin`

### 决策 3：版本默认值

**选择**: `OPENSPEC_VERSION=1.2.0`

**理由**:
- 当前最新稳定版本
- 与其他工具版本命名风格一致（如 `NEOVIM_VERSION=0.11.6`）

## Risks / Trade-offs

**风险**: OpenSpec 版本更新频繁（从 0.1.0 到 1.2.0 在半年内发布）
→ **缓解**: 通过 ARG 参数可随时调整版本

**风险**: npm 安装依赖网络稳定性
→ **缓解**: 依赖 Node.js 安装已成功的前提