# Auto Rebuild Fullstack on CLI Version Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建定时 GitHub Actions 工作流，每 4 小时检查 Claude Code 和 Codex CLI 是否有新 release，自动触发 batch 重建。

**Architecture:** 新建一个独立工作流 `check-fullstack-updates.yml`，通过 GitHub API 查询工具 release 时间和 GHCR 镜像构建时间，比较后通过 PAT 触发 `build-fullstack-batch.yml`。不改动现有工作流和 Dockerfile。

**Tech Stack:** GitHub Actions, GitHub CLI (`gh api`, `gh workflow run`), `jq`, `yq`

## Global Constraints

- 不进行本地测试，所有验证通过 GitHub Actions 远程运行
- 权限最小化：`contents: read`、`packages: read`
- 跨 workflow 触发使用 PAT（`secrets.REBUILD_PAT`）
- cron: `0 */4 * * *`（每 4 小时）
- 支持 `workflow_dispatch` 手动触发
- 保持与现有工作流一致的代码风格（shell 脚本、步骤命名、注释密度）

---

### Task 1: Create the check-fullstack-updates workflow

**Files:**
- Create: `.github/workflows/check-fullstack-updates.yml`

**Interfaces:**
- Produces: workflow 对外通过 `gh workflow run build-fullstack-batch.yml --ref main` 触发重建
- Depends on: `secrets.REBUILD_PAT`（需手动在 GitHub 仓库设置中创建）

- [ ] **Step 1: Create the workflow file**

```bash
cat > .github/workflows/check-fullstack-updates.yml << 'EOF'
name: Check Fullstack Updates

on:
  schedule:
    - cron: "0 */4 * * *"
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

          if [ "$CLAUDE_TS" -gt "$CODEX_TS" ]; then
            echo "latest_ts=$CLAUDE_TS" >> $GITHUB_OUTPUT
          else
            echo "latest_ts=$CODEX_TS" >> $GITHUB_OUTPUT
          fi

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
          echo "触发原因: ${{ steps.check.outputs.reason }}"
          gh workflow run build-fullstack-batch.yml --ref main
EOF
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
wc -l .github/workflows/check-fullstack-updates.yml && \
  head -3 .github/workflows/check-fullstack-updates.yml
```

Expected: file exists with ~75 lines, starts with `name: Check Fullstack Updates`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/check-fullstack-updates.yml
git commit -m "feat: add auto-rebuild check workflow for CLI version updates

Per 4-hour cron check: queries Claude Code and Codex CLI latest release
timestamps from GitHub API, compares against batch image build times in
GHCR, and triggers build-fullstack-batch when any image is outdated.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Update CLAUDE.md workflow list

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: 依赖 Task 1 创建的 `check-fullstack-updates.yml`

- [ ] **Step 1: Add the new workflow to the CI/CD 工作流 list**

Open `CLAUDE.md` and insert after the `build-pg-ddl-sync.yml` line:

```markdown
- `.github/workflows/check-fullstack-updates.yml` - Fullstack CLI 版本更新检测
```

The relevant section should look like:

```markdown
- `.github/workflows/build-pg-ddl-sync.yml` - PostgreSQL DDL 同步伴生服务
- `.github/workflows/check-fullstack-updates.yml` - Fullstack CLI 版本更新检测
```

- [ ] **Step 2: Verify the edit**

```bash
grep "check-fullstack-updates" CLAUDE.md
```

Expected: one matching line

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add check-fullstack-updates workflow to CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Post-deployment manual setup

> ⚠️ 此 task 不能自动化执行，需要在 GitHub 仓库页面手动操作。

**需要完成的操作:**

- [ ] **Step 1: 创建 Fine-grained PAT**

1. 进入 GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. 点击 "Generate new token"
3. 设置:
   - Resource owner: 你的账户
   - Repository access: "Only select repositories" → 选 `self-docker-build-image`
   - Permissions: `actions: write`（仅此一项）
4. 生成后复制 token

- [ ] **Step 2: 将 PAT 添加为仓库 Secret**

1. 进入仓库 → Settings → Secrets and variables → Actions
2. 点击 "New repository secret"
3. Name: `REBUILD_PAT`
4. Value: 粘贴上一步的 PAT
5. 点击 "Add secret"

- [ ] **Step 3: 手动触发一次验证**

1. 进入 Actions 标签页
2. 选择 "Check Fullstack Updates"
3. 点击 "Run workflow"
4. 检查运行日志确认各个步骤正常执行
5. 检查 build-fullstack-batch 是否被触发（如果镜像版本过旧的话）
