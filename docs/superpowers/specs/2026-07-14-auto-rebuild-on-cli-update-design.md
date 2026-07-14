# Auto Rebuild Fullstack on CLI Version Update

## 概述

创建定时 GitHub Actions 工作流，每 4 小时自动检查 Claude Code (`anthropics/claude-code`) 和 Codex CLI (`openai/codex`) 是否有新版本发布。如果任一工具在 batch 镜像构建之后有新 release，自动触发 `build-fullstack-batch` 重建全部场景镜像。

## 背景

目前 `fullstack-image/fullstack.Dockerfile` 在构建时安装两个 CLI 工具：

| 工具 | 安装方式 | 版本控制 |
|------|---------|---------|
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash -s -- ${CLAUDE_VERSION}` | `CLAUDE_VERSION=latest`（默认） |
| Codex CLI | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | `CODEX_VERSION=latest`（默认） |

由于 Docker 构建缓存的存在，即使上游发布了新版本，镜像也不会自动更新。需要定时检测并触发重建。

## 设计

### 判断逻辑

```
# 获取最新 release 时间
Claude Code latest release published_at → T_claude
Codex CLI  latest release published_at → T_codex
T_latest = max(T_claude, T_codex)

# 获取 batch 镜像各 tag 的构建时间
for tag in [android, web.24, yzj, p, yzj.web]:
    T_tag = ghcr.io 中该 tag 对应 version 的 created_at
    if T_tag < T_latest:
        → 需要重建
        → 触发 build-fullstack-batch.yml

# 未构建过的 tag 也视为需要重建
```

### 数据源

| 数据 | API |
|------|-----|
| Claude Code 最新 release 时间 | `gh api repos/anthropics/claude-code/releases/latest --jq '.published_at'` |
| Codex CLI 最新 release 时间 | `gh api repos/openai/codex/releases/latest --jq '.published_at'` |
| Batch 镜像 tag 构建时间 | `gh api /users/{owner}/packages/container/fullstack/versions --paginate`（按 tag 筛选） |

### 工作流文件

`.github/workflows/check-fullstack-updates.yml`

```yaml
name: Check Fullstack Updates

on:
  schedule:
    - cron: "0 */4 * * *"   # 每4小时
  workflow_dispatch:

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read

    steps:
      - uses: actions/checkout@v6

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq \
            https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Get latest release timestamps
        id: releases
        run: |
          CLAUDE_TIME=$(gh api repos/anthropics/claude-code/releases/latest \
            --jq '.published_at')
          CODEX_TIME=$(gh api repos/openai/codex/releases/latest \
            --jq '.published_at')

          CLAUDE_TS=$(date -d "$CLAUDE_TIME" +%s)
          CODEX_TS=$(date -d "$CODEX_TIME" +%s)

          [ "$CLAUDE_TS" -gt "$CODEX_TS" ] && \
            echo "latest_ts=$CLAUDE_TS" >> $GITHUB_OUTPUT || \
            echo "latest_ts=$CODEX_TS" >> $GITHUB_OUTPUT

      - name: Check if rebuild needed
        id: check
        run: |
          LATEST_TS=${{ steps.releases.outputs.latest_ts }}
          OWNER=${{ github.repository_owner }}

          TAGS=$(yq '.scenarios.[].tag' fullstack-image/scenarios.yaml)

          VERSIONS=$(gh api "/users/${OWNER}/packages/container/fullstack/versions" \
            --paginate 2>/dev/null | jq -s 'add' 2>/dev/null || echo "[]")

          for TAG in $TAGS; do
            TAG_TIME=$(echo "$VERSIONS" | \
              jq -r "[.[] | select(.metadata.container.tags[]? == \"$TAG\")] | first | .created_at // \"never\"")

            if [ "$TAG_TIME" = "never" ]; then
              echo "need_rebuild=true" >> $GITHUB_OUTPUT
              echo "reason=$TAG 从未构建过" >> $GITHUB_OUTPUT
              exit 0
            fi

            TAG_TS=$(date -d "$TAG_TIME" +%s)
            if [ "$TAG_TS" -lt "$LATEST_TS" ]; then
              echo "need_rebuild=true" >> $GITHUB_OUTPUT
              echo "reason=$TAG 版本过旧(构建于 $TAG_TIME)" >> $GITHUB_OUTPUT
              exit 0
            fi
          done

          echo "need_rebuild=false" >> $GITHUB_OUTPUT

      - name: Trigger batch rebuild
        if: steps.check.outputs.need_rebuild == 'true'
        env:
          GH_TOKEN: ${{ secrets.REBUILD_PAT }}
        run: |
          echo "原因: ${{ steps.check.outputs.reason }}"
          gh workflow run build-fullstack-batch.yml --ref main
```

## 依赖

### 新增 Secret

| Secret | 说明 |
|--------|------|
| `REBUILD_PAT` | GitHub Personal Access Token (fine-grained)，权限 `actions: write` 限于当前仓库，用于跨 workflow 触发 |

GITHUB_TOKEN 无法触发其他 workflow 的 `workflow_dispatch`，必须使用 PAT。

### 权限说明

- `contents: read` — 读取仓库代码和 `scenarios.yaml`
- `packages: read` — 读取 GHCR 包和版本元数据
- 触发 batch 构建使用 `REBUILD_PAT`，不需要 `actions: write` 权限

## 边界情况

| 场景 | 处理 |
|------|------|
| 镜像从未构建过 | GHCR API 返回空，该 tag 的 `created_at` 为 `"never"`，触发首次构建 |
| GHCR 版本记录超过 30 条 | 使用 `--paginate` + `jq -s 'add'` 合并所有页 |
| 两个工具同时有更新 | `max()` 逻辑自然覆盖，取任意更新的 release 时间 |
| 检查工作流自身失败 | GitHub Actions 日志可查看，不影响已有镜像 |
| Codex release tag 格式为 `rust-v0.144.4` | 只比较时间戳，不解析 tag 版本号 |

## 不涉及

- 邮件通知（后续可加）
- 修改现有 `build-fullstack-batch.yml`
- 修改 Dockerfile 中的版本号默认值
