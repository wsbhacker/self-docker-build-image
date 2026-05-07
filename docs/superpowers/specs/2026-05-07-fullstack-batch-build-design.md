# Fullstack 镜像批量构建方案设计

## 背景

当前 `fullstack.Dockerfile` 支持多个构建参数（JDK_VERSION、NODE_VERSION、MAVEN_VERSION 等），不同使用场景需要不同的参数组合。现有 workflow 每次只能构建一个参数组合的镜像，多个场景需要多次手动触发，效率较低。

## 目标

实现批量构建能力：一次触发可构建多个预定义场景的镜像，支持并行构建，易于扩展新场景。

## 设计方案

### 架构

```
fullstack-image/
├── fullstack.Dockerfile      # 基础镜像定义
├── scenarios.yaml            # 场景配置文件（新增）
└── entrypoint.sh

.github/workflows/
├── build-fullstack.yml       # 单场景构建（保留现有）
└── build-fullstack-batch.yml # 批量构建（新增）
```

### 场景配置文件

**路径：** `fullstack-image/scenarios.yaml`

**结构：**
```yaml
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

**字段说明：**
- `description`：场景描述，用于构建记录
- `tag`：镜像标签，最终镜像为 `ghcr.io/{owner}/fullstack:{tag}`
- `build_args`：构建参数键值对，传递给 docker build

**扩展方式：**
新增场景只需在 `scenarios.yaml` 添加条目，无需修改 workflow。

### 批量构建 Workflow

**路径：** `.github/workflows/build-fullstack-batch.yml`

**触发条件：**
```yaml
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
```

**触发方式：**
| 场景 | 触发方式 |
|------|---------|
| 手动全量构建 | workflow_dispatch，scenarios 参数留空 |
| 手动指定构建 | workflow_dispatch，scenarios 参数输入场景列表 |
| Dockerfile 变更 | push 自动触发，构建全部场景 |
| scenarios.yaml 变更 | 不自动触发，需手动触发 |

**Workflow 结构：**
```yaml
jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      scenarios: ${{ steps.parse.outputs.scenarios }}
    steps:
      - uses: actions/checkout@v4
      - name: Parse scenarios
        id: parse
        run: |
          # 使用 yq 解析 scenarios.yaml
          # 根据 inputs.scenarios 过滤或获取全部
          # 输出 JSON 数组

  build:
    needs: prepare
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        scenario: ${{ fromJson(needs.prepare.outputs.scenarios) }}
    steps:
      - uses: actions/checkout@v4
      - name: Log in to GHCR
      - name: Set up QEMU
      - name: Set up Docker Buildx
      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: ./fullstack-image
          file: ./fullstack-image/fullstack.Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/fullstack:${{ matrix.scenario.tag }}
          build-args: ...
          platforms: linux/amd64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**关键实现：**
- `prepare` job 解析 YAML，生成 JSON 数组
- `build` job 使用 matrix 并行构建，单场景失败不影响其他（`fail-fast: false`）
- 镜像标签使用场景配置中的 `tag` 字段
- 构建参数从 `build_args` 提取并格式化

### 与现有 Workflow 的关系

| Workflow | 用途 |
|---------|------|
| `build-fullstack.yml` | 单场景临时构建、特殊参数调试、push 自动构建默认镜像 |
| `build-fullstack-batch.yml` | 批量构建预定义场景 |

两个 workflow 独立运行，互不影响。

### 错误处理

- 单场景构建失败：不影响其他场景继续构建
- 配置文件格式错误：prepare job 直接失败并提示错误
- 场景名称不存在：prepare job 失败并提示未定义场景

### 镜像回滚

如 Dockerfile 变更导致镜像问题：
1. 回滚 Dockerfile 到历史版本
2. 手动触发 batch workflow 重新构建

### 并行限制

GitHub Actions 公共仓库最大并发 20 个 job，超出自动排队等待。当前场景数量约 5 个，无需额外限制。

## 使用示例

### 新增场景

1. 编辑 `fullstack-image/scenarios.yaml`，添加新条目
2. 提交推送
3. 手动触发 `build-fullstack-batch.yml`

### 修改场景

1. 编辑 `scenarios.yaml` 更新参数
2. 手动触发构建

### 选择性构建

手动触发时输入 `scenarios: jdk11-dev,node14-dev`，只构建这两个场景。

### 全量构建

手动触发时 `scenarios` 参数留空，构建全部定义的场景。