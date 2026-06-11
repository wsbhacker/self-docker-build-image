# Fullstack 镜像构建标识设计

## 背景

用户在使用 fullstack 镜像时，经常同时运行多个不同场景的容器（如 `android`, `yzj.web`, `p` 等）。需要在容器内快速识别当前所在容器的镜像来源和构建时间。

## 目标

- 进入容器后可通过 `echo $CID` 查看完整标识
- 进入容器后可通过 `echo $CTAG` 查看纯 tag
- 标识格式：`tag:yyyy-MM-dd HH:mm:ss`（如 `android:2026-06-11 14:30:52`）

## 设计

### 环境变量

| 变量名 | 格式 | 示例值 | 说明 |
|--------|------|--------|------|
| `CID` | `{tag}:{timestamp}` | `android:2026-06-11 14:30:52` | 完整标识，主要使用 |
| `CTAG` | `{tag}` | `android` | 仅 tag，简洁版 |

### 变量名选择理由

- `CID`：Container ID 的缩写，语义清晰，无冲突
- `CTAG`：Container Tag 的缩写，语义清晰，无冲突
- 非 Docker/Shell 标准变量，不会冲突

## 实现方案

### 改动文件

| 文件 | 改动 |
|------|------|
| `fullstack-image/fullstack.Dockerfile` | 添加 ARG/ENV |
| `.github/workflows/build-fullstack-batch.yml` | 添加时间戳 + 传参 |
| `.github/workflows/build-fullstack.yml` | 添加时间戳 + 传参 |

### Dockerfile 改动

在全局 ARG 区域添加：

```dockerfile
ARG IMAGE_TAG=default
ARG BUILD_TIMESTAMP=default
```

在 ENV 区域添加：

```dockerfile
ENV CTAG=${IMAGE_TAG}
ENV CID=${IMAGE_TAG}:${BUILD_TIMESTAMP}
```

### Workflow 改动

两个 workflow 统一添加：

```yaml
- name: Set build timestamp
  id: timestamp
  run: echo "value=$(date '+%Y-%m-%d %H:%M:%S')" >> $GITHUB_OUTPUT
```

build-args 传入：

```yaml
build-args: |
  IMAGE_TAG=<tag来源>
  BUILD_TIMESTAMP=${{ steps.timestamp.outputs.value }}
```

### IMAGE_TAG 来源

| Workflow | 触发方式 | IMAGE_TAG 值 |
|----------|---------|--------------|
| `build-fullstack-batch.yml` | 任意 | `matrix.scenario.tag`（来自 scenarios.yaml） |
| `build-fullstack.yml` | 手动触发 | `inputs.version_tag` 或默认 `latest` |
| `build-fullstack.yml` | Push 触发 | 固定 `fullstack` |

## 用户使用示例

```bash
neo@container:~$ echo $CID
android:2026-06-11 14:30:52

neo@container:~$ echo $CTAG
android
```

## 验证方式

1. 构建镜像后，本地运行容器测试 `echo $CID` 和 `echo $CTAG`
2. 检查输出格式是否符合预期

## 不在范围内

- Shell prompt 自动显示标识（用户可自行在 `.zshrc` 中配置）
- 区分同一镜像的不同容器实例（无需此功能）