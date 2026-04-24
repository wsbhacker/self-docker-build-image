# Android SDK Docker 镜像设计

## 背景

基于现有 `fullstack-image/fullstack.Dockerfile` 扩展，添加 Android SDK 支持，实现一个镜像支持全栈开发 + Android 项目编译。

## 需求总结

| 需求项 | 决策 |
|--------|------|
| 构建系统 | Gradle（项目自带，无需预装） |
| 原生代码 | 无（不需要 NDK） |
| 目标架构 | 仅编译 arm64-v8a APK |
| JDK 版本 | 继承现有配置（构建时自行指定） |
| 使用场景 | 本地开发环境 |
| 额外功能 | zsh、tmux（继承 fullstack） |

## 设计决策

### SDK 安装时机：运行时安装

**原因**：
- 避免 Volume 挂载覆盖镜像内已安装的 cmdline-tools
- 用户可灵活指定任意 SDK 版本
- 镜像体积更小（约 200MB vs 500MB+）
- SDK 通过 Volume 持久化，首次安装后后续启动无需等待

### 核心组件

| 组件 | 版本 | 来源 |
|------|------|------|
| JDK | 可配置（默认 17） | Eclipse Temurin |
| cmdline-tools | 14742923（最新） | Google 官方下载 |
| build-tools | 可配置（默认 34.0.0） | 运行时 sdkmanager 安装 |
| platforms | 可配置（默认 android-34） | 运行时 sdkmanager 安装 |

## 修改文件

### 1. fullstack.Dockerfile

**新增 ARG**（全局，第 3-6 行附近）：
```dockerfile
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
```

**新增 ARG**（FROM 后，第 15-28 行附近）：
```dockerfile
ARG TARGET_PLATFORM=android-34
ARG BUILD_TOOLS_VERSION=34.0.0
```

**新增 ENV**（第 50-51 行附近）：
```dockerfile
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION}
ENV TARGET_PLATFORM=${TARGET_PLATFORM}
ENV BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION}
```

**修改 PATH**（第 54 行，合并到一行）：
```dockerfile
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```

**新增目录创建**（第 104 行附近，创建目录后）：
```dockerfile
# ==========================================
# XX. 创建 Android SDK 目录
# ==========================================
RUN mkdir -p ${ANDROID_HOME} && \
    chown -R ${USERNAME}:${USERNAME} ${ANDROID_HOME}
```

### 2. entrypoint.sh

添加 Android SDK 检查和安装逻辑：

```bash
# 检查并安装 Android SDK
if [ ! -f "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Installing Android SDK..."

  # 确保目录权限
  sudo chown -R ${USERNAME}:${USERNAME} ${ANDROID_HOME} 2>/dev/null || true

  # 下载 cmdline-tools
  ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION:-14742923}
  wget https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip \
    -O /tmp/cmdline-tools.zip

  # 解压并安装
  mkdir -p ${ANDROID_HOME}/cmdline-tools
  unzip /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools
  mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest
  rm /tmp/cmdline-tools.zip

  # 接受许可证
  yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1 || true

  # 安装 SDK 组件
  ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
    "platforms;${TARGET_PLATFORM:-android-34}" \
    "build-tools;${BUILD_TOOLS_VERSION:-34.0.0}" \
    "platform-tools"
fi
```

### 3. GitHub Workflow

现有 `.github/workflows/build-fullstack.yml` 已支持 build-args 传参，无需修改。

使用示例：
```yaml
# GitHub Actions 手动触发时传入参数
build_args: "JDK_VERSION=21;TARGET_PLATFORM=android-35;BUILD_TOOLS_VERSION=35.0.0"
```

## 使用方式

### 构建镜像

```bash
docker build \
  --build-arg JDK_VERSION=17 \
  --build-arg TARGET_PLATFORM=android-34 \
  --build-arg BUILD_TOOLS_VERSION=34.0.0 \
  -t fullstack:latest \
  ./fullstack-image
```

### 运行容器

```bash
# SDK 首次启动时安装到挂载目录（持久化）
docker run -it \
  -v ./android-sdk:/opt/android-sdk \
  -v ./zsh:/home/neo/zsh \
  -v ./workspace:/home/neo/work \
  -e TARGET_PLATFORM=android-35 \
  -e BUILD_TOOLS_VERSION=35.0.0 \
  fullstack:latest /bin/bash
```

### 编译 Android 项目

```bash
# 在容器内
cd /home/neo/work/my-android-app
./gradlew assembleRelease
```

## 预估镜像体积

| 组件 | 体积 |
|------|------|
| Eclipse Temurin JDK 17 | ~300MB |
| 基础工具（wget、unzip 等） | 已包含 |
| cmdline-tools（运行时下载） | ~170MB |
| build-tools + platforms（运行时下载） | ~200MB |
| **镜像本身** | **~300MB**（不含 SDK） |

## 已解决的问题

| 问题 | 解决方案 |
|------|---------|
| PATH 环境变量覆盖 | 合并到一行 ENV PATH |
| Volume 挂载覆盖容器内容 | 镜像不安装 SDK，运行时安装到挂载目录 |
| cmdline-tools 版本过时 | 使用最新版本 14742923 |
| 挂载目录权限不匹配 | Entrypoint 中 sudo chown |
| sdkmanager 许可证交互 | yes 管道输入 |
| 多架构构建 | 镜像 amd64，可编译 arm64 APK |

## 参考资料

- [Android Studio Command-line Tools](https://developer.android.com/studio#command-line-tools-only)
- [thyrlian/AndroidSdk GitHub](https://github.com/thyrlian/AndroidSdk)