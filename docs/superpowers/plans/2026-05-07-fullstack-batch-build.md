# Fullstack Batch Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add batch build capability for fullstack Docker image, enabling one-trigger multi-scenario parallel builds via scenarios.yaml configuration.

**Architecture:** Configuration-driven approach with scenarios.yaml defining build parameters per scenario. A new GitHub Actions workflow parses the config and uses matrix strategy for parallel builds. Existing single-scenario workflow remains unchanged.

**Tech Stack:** GitHub Actions, YAML, yq (YAML processor), Docker build-push-action, Matrix strategy

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `fullstack-image/scenarios.yaml` | Create | Scene configuration with tag, description, build_args |
| `.github/workflows/build-fullstack-batch.yml` | Create | Batch build workflow with prepare + matrix build jobs |

---

### Task 1: Create scenarios.yaml Configuration File

**Files:**
- Create: `fullstack-image/scenarios.yaml`

- [ ] **Step 1: Write scenarios.yaml with initial scenarios**

Create file with 4 example scenarios covering common use cases:

```yaml
# Fullstack 镜像场景配置
# 每个场景定义独立的构建参数组合
# 新增场景只需添加新条目，无需修改 workflow

scenarios:
  jdk11-dev:
    description: "JDK 11 开发环境"
    tag: jdk11
    build_args:
      JDK_VERSION: 11

  node14-dev:
    description: "Node 14 开发环境"
    tag: node14
    build_args:
      NODE_VERSION: 14

  jdk8-node20:
    description: "JDK 8 + Node 20 混合环境"
    tag: jdk8-node20
    build_args:
      JDK_VERSION: 8
      NODE_VERSION: 20

  maven31-dev:
    description: "Maven 3.1 开发环境"
    tag: maven31
    build_args:
      MAVEN_VERSION: 3.1
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('fullstack-image/scenarios.yaml'))"`
Expected: No error output (valid YAML)

- [ ] **Step 3: Commit scenarios.yaml**

```bash
git add fullstack-image/scenarios.yaml
git commit -m "feat: add scenarios.yaml for batch build configuration

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 2: Create Batch Build Workflow

**Files:**
- Create: `.github/workflows/build-fullstack-batch.yml`

- [ ] **Step 1: Write workflow file with trigger configuration and prepare job**

Create the workflow with workflow_dispatch input and push trigger for Dockerfile changes. Include prepare job that parses scenarios.yaml:

```yaml
name: Build Fullstack Batch

on:
  workflow_dispatch:
    inputs:
      scenarios:
        description: "指定场景名称（逗号分隔，如：jdk11-dev,node14-dev），留空则构建全部"
        required: false
        default: ""
        type: string

  push:
    branches: [main]
    paths:
      - "fullstack-image/fullstack.Dockerfile"

env:
  REGISTRY: ghcr.io

jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.parse.outputs.matrix }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Parse scenarios
        id: parse
        run: |
          # 读取 scenarios.yaml
          SCENARIOS_FILE="fullstack-image/scenarios.yaml"

          if [ ! -f "$SCENARIOS_FILE" ]; then
            echo "Error: scenarios.yaml not found"
            exit 1
          fi

          # 获取所有场景名称
          ALL_SCENARIOS=$(yq e '.scenarios | keys | .[]' "$SCENARIOS_FILE")

          # 判断是否指定了场景
          if [ -n "${{ inputs.scenarios }}" ]; then
            # 过滤指定场景
            SELECTED_SCENARIOS="${{ inputs.scenarios }}"
            IFS=',' read -ra SCENARIO_NAMES <<< "$SELECTED_SCENARIOS"

            # 验证场景是否存在
            for name in "${SCENARIO_NAMES[@]}"; do
              name=$(echo "$name" | xargs)  # trim whitespace
              if ! echo "$ALL_SCENARIOS" | grep -qw "$name"; then
                echo "Error: Scenario '$name' not defined in scenarios.yaml"
                exit 1
              fi
            done

            SCENARIO_LIST="$SELECTED_SCENARIOS"
          else
            # 构建全部场景
            SCENARIO_LIST=$(echo "$ALL_SCENARIOS" | tr '\n' ',' | sed 's/,$//')
          fi

          # 构建 JSON 数组输出
          MATRIX_JSON="[]"
          IFS=',' read -ra SCENARIOS <<< "$SCENARIO_LIST"
          for scenario_name in "${SCENARIOS[@]}"; do
            scenario_name=$(echo "$scenario_name" | xargs)

            # 提取场景配置
            tag=$(yq e ".scenarios.${scenario_name}.tag" "$SCENARIOS_FILE")
            description=$(yq e ".scenarios.${scenario_name}.description" "$SCENARIOS_FILE")

            # 提取 build_args 并格式化
            build_args_json=$(yq e ".scenarios.${scenario_name}.build_args | to_json" "$SCENARIOS_FILE")

            # 构建 JSON 对象
            SCENARIO_OBJ=$(jq -n \
              --arg name "$scenario_name" \
              --arg tag "$tag" \
              --arg description "$description" \
              --argjson build_args "$build_args_json" \
              '{name: $name, tag: $tag, description: $description, build_args: $build_args}')

            MATRIX_JSON=$(echo "$MATRIX_JSON" | jq --argjson obj "$SCENARIO_OBJ" '. += [$obj]')
          done

          echo "matrix=$(echo "$MATRIX_JSON" | jq -c .)" >> $GITHUB_OUTPUT
          echo "Scenarios to build:"
          echo "$MATRIX_JSON" | jq '.[].name'

        shell: bash

  build:
    needs: prepare
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false
      matrix:
        scenario: ${{ fromJson(needs.prepare.outputs.matrix) }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Format build args
        id: format-args
        run: |
          # 将 build_args JSON 转换为多行格式
          BUILD_ARGS=""
          for key in $(echo '${{ matrix.scenario.build_args }}' | jq -r 'keys[]'); do
            value=$(echo '${{ matrix.scenario.build_args }}' | jq -r ".\"$key\"")
            BUILD_ARGS="${BUILD_ARGS}${key}=${value}"$'\n'
          done
          echo "args<<EOF" >> $GITHUB_OUTPUT
          echo -n "$BUILD_ARGS" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT
        shell: bash

      - name: Build and push image
        uses: docker/build-push-action@v7
        with:
          context: ./fullstack-image
          file: ./fullstack-image/fullstack.Dockerfile
          push: true
          tags: ${{ env.REGISTRY }}/${{ github.repository_owner }}/fullstack:${{ matrix.scenario.tag }}
          build-args: ${{ steps.format-args.outputs.args }}
          platforms: linux/amd64
          cache-from: type=gha
          cache-to: type=gha,mode=max
          labels: |
            org.opencontainers.image.description=${{ matrix.scenario.description }}
            org.opencontainers.image.title=Fullstack Dev Image - ${{ matrix.scenario.name }}
```

- [ ] **Step 2: Validate workflow YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-fullstack-batch.yml'))"`
Expected: No error output (valid YAML)

- [ ] **Step 3: Commit workflow file**

```bash
git add .github/workflows/build-fullstack-batch.yml
git commit -m "feat: add batch build workflow for fullstack image

- Add scenarios.yaml parser with validation
- Use matrix strategy for parallel builds
- Support selective or full scenario builds
- Auto-trigger on Dockerfile changes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] scenarios.yaml configuration file - Task 1
- [x] Batch build workflow - Task 2
- [x] workflow_dispatch with scenarios input - Task 2, Step 1
- [x] Push trigger on Dockerfile changes - Task 2, Step 1
- [x] Matrix parallel builds - Task 2, Step 1
- [x] fail-fast: false for isolation - Task 2, Step 1
- [x] Scenario validation (non-existent scenario fails prepare) - Task 2, Step 1 (grep validation)
- [x] Build args formatting - Task 2, Step 1 (format-args step)

**Placeholder scan:** No TBD, TODO, or vague descriptions found.

**Type consistency:** All references to `matrix.scenario.tag`, `matrix.scenario.build_args`, `matrix.scenario.name` are consistent throughout the workflow.

---

## Execution Notes

This workflow cannot be tested locally (GitHub Actions runtime required). After pushing to GitHub:

1. Go to Actions page
2. Select "Build Fullstack Batch" workflow
3. Run with empty scenarios input to test full build
4. Run with specific scenarios (e.g., `jdk11-dev`) to test selective build
5. Verify matrix jobs spawn correctly
6. Check individual job logs for build success/failure