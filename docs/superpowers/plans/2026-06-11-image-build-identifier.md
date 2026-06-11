# 镜像构建标识实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 fullstack 镜像添加构建标识环境变量 CID 和 CTAG，用户可在容器内通过 `echo $CID` 查看镜像 tag 和构建时间。

**Architecture:** 通过 Dockerfile ARG/ENV 在构建时注入标识，两个 workflow 分别传入 IMAGE_TAG 和 BUILD_TIMESTAMP。

**Tech Stack:** Dockerfile ARG/ENV, GitHub Actions workflow, shell 环境变量

---

## 文件改动概览

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `fullstack-image/fullstack.Dockerfile` | 修改 | 添加 ARG IMAGE_TAG/BUILD_TIMESTAMP，ENV CTAG/CID |
| `.github/workflows/build-fullstack-batch.yml` | 修改 | 添加时间戳生成 step，传入 build-args |
| `.github/workflows/build-fullstack.yml` | 修改 | 添加时间戳生成 step，传入 build-args |

---

### Task 1: 修改 Dockerfile 添加 ARG 和 ENV

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile`

- [ ] **Step 1: 在全局 ARG 区域添加新 ARG**

在第 8 行 `ARG GIT_VERSION=latest` 后添加：

```dockerfile
ARG IMAGE_TAG=default
ARG BUILD_TIMESTAMP=default
```

- [ ] **Step 2: 在 FROM 后重新声明 ARG**

在第 38 行 `ARG GIT_VERSION=latest` 后添加：

```dockerfile
ARG IMAGE_TAG=default
ARG BUILD_TIMESTAMP=default
```

- [ ] **Step 3: 在 ENV 区域添加 CTAG 和 CID**

在第 71 行 `ENV BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION}` 后添加：

```dockerfile
ENV IMAGE_TAG=${IMAGE_TAG}
ENV BUILD_TIMESTAMP=${BUILD_TIMESTAMP}
ENV CTAG=${IMAGE_TAG}
ENV CID=${IMAGE_TAG}:${BUILD_TIMESTAMP}
```

- [ ] **Step 4: 提交改动**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "feat: add IMAGE_TAG and BUILD_TIMESTAMP ARG/ENV for container identification

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 修改 build-fullstack-batch.yml

**Files:**
- Modify: `.github/workflows/build-fullstack-batch.yml`

- [ ] **Step 1: 在 build job 中添加时间戳生成 step**

在 `Set up Docker Buildx` step 后（约第 128 行）添加：

```yaml
      - name: Set build timestamp
        id: timestamp
        run: echo "value=$(date '+%Y-%m-%d %H:%M:%S')" >> $GITHUB_OUTPUT
```

- [ ] **Step 2: 修改 build-args 传入 IMAGE_TAG 和 BUILD_TIMESTAMP**

将原有的 `build-args` 修改为：

```yaml
          build-args: |
            IMAGE_TAG=${{ matrix.scenario.tag }}
            BUILD_TIMESTAMP=${{ steps.timestamp.outputs.value }}
            ${{ steps.format-args.outputs.args }}
```

注意：保留原有的 `${{ steps.format-args.outputs.args }}` 以支持场景自定义 build_args。

- [ ] **Step 3: 提交改动**

```bash
git add .github/workflows/build-fullstack-batch.yml
git commit -m "feat: pass IMAGE_TAG and BUILD_TIMESTAMP to Dockerfile in batch build

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 修改 build-fullstack.yml

**Files:**
- Modify: `.github/workflows/build-fullstack.yml`

- [ ] **Step 1: 在 build-and-push job 中添加时间戳生成 step**

在 `Set up Docker Buildx` step 后（约第 59 行）添加：

```yaml
      - name: Set build timestamp
        id: timestamp
        run: echo "value=$(date '+%Y-%m-%d %H:%M:%S')" >> $GITHUB_OUTPUT
```

- [ ] **Step 2: 添加 IMAGE_TAG 计算步骤**

在时间戳 step 后添加：

```yaml
      - name: Set image tag
        id: image-tag
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            TAG="${{ inputs.version_tag }}"
          else
            TAG="fullstack"
          fi
          echo "value=${TAG}" >> $GITHUB_OUTPUT
```

- [ ] **Step 3: 修改 Build and push image step 的 build-args**

将原有的 `build-args: ${{ steps.parse-args.outputs.args }}` 修改为：

```yaml
          build-args: |
            IMAGE_TAG=${{ steps.image-tag.outputs.value }}
            BUILD_TIMESTAMP=${{ steps.timestamp.outputs.value }}
            ${{ steps.parse-args.outputs.args }}
```

- [ ] **Step 4: 提交改动**

```bash
git add .github/workflows/build-fullstack.yml
git commit -m "feat: pass IMAGE_TAG and BUILD_TIMESTAMP to Dockerfile in single build

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 最终提交汇总（可选）

**Files:**
- 无新文件

- [ ] **Step 1: 确认所有改动已提交**

```bash
git status
git log --oneline -5
```

预期输出：看到 3 个新的 commit（Task 1-3 的提交）。

---

## 验证方式

用户自行验证：
1. 推送改动到 GitHub
2. 触发 workflow 构建镜像
3. 运行容器后执行 `echo $CID` 和 `echo $CTAG`
4. 检查输出格式是否为 `tag:yyyy-MM-dd HH:mm:ss`