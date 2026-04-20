# Claude Code 版本控制设计

## 背景

`fullstack.Dockerfile` 中已有多个工具的版本控制机制（JDK、Maven、Node.js、Python 等），通过 ARG/ENV 模式实现。Claude Code 当前使用 `curl -fsSL https://claude.ai/install.sh | bash` 安装，始终安装最新版本，无法指定版本。

## 目标

为 Claude Code 安装添加版本控制能力，与现有工具版本控制模式保持一致。

## 设计

### 变更点

| 位置 | 操作 | 内容 |
|------|------|------|
| 全局 ARG 区域（第4行附近） | 添加 | `ARG CLAUDE_VERSION=latest` |
| FROM 后 ARG 区域（第14行附近） | 添加 | `ARG CLAUDE_VERSION=latest` |
| ENV 区域（第35行附近） | 添加 | `ENV CLAUDE_VERSION=${CLAUDE_VERSION}` |
| 安装命令（第148行） | 修改 | 添加版本参数传递 |

### 具体代码变更

**1. 全局 ARG（第4行后）：**
```dockerfile
ARG CLAUDE_VERSION=latest
```

**2. FROM 后 ARG 重新声明（第14行附近）：**
```dockerfile
ARG CLAUDE_VERSION=latest
```

**3. ENV 转换（第35行附近）：**
```dockerfile
ENV CLAUDE_VERSION=${CLAUDE_VERSION}
```

**4. 安装命令修改（第148行）：**

原代码：
```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash
```

改为：
```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION}
```

## 使用方式

```bash
# 默认安装最新版
docker build -t fullstack .

# 安装指定版本
docker build --build-arg CLAUDE_VERSION=2.1.114 -t fullstack .

# 安装 stable 版本
docker build --build-arg CLAUDE_VERSION=stable -t fullstack .
```

## 支持的版本格式

根据官方 install.sh 脚本，支持以下格式：
- `latest` - 最新版本
- `stable` - 稳定版本
- `X.Y.Z` - 精确版本号（如 `2.1.114`）
- `X.Y.Z-xxx` - 带后缀的版本号

## 验证

* 无需验证
