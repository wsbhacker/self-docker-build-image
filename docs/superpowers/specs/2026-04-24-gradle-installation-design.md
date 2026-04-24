# Gradle 安装设计文档

## 背景

在 fullstack-image 中添加 Gradle 安装支持，满足以下需求：
- 用于非 Android 的 Java/Kotlin 项目构建（Maven 的替代方案）
- 用于 Android 项目构建（Gradle wrapper 外的系统级工具支持）

## 设计决策

### 版本控制

| 参数 | 值 |
|------|-----|
| ARG 名称 | `GRADLE_VERSION` |
| 默认值 | `9.4.1`（2026-04 最新稳定版） |
| 配置方式 | 通过 GitHub workflow `build_args` 参数传入，格式 `GRADLE_VERSION=9.4.1` |

参考 Gradle 官方发布页：https://gradle.org/releases/

### 安装位置

| 目录 | 路径 | 说明 |
|------|------|------|
| 安装目录 | `~/opt/gradle` | 与 Maven、Neovim 保持一致，可挂载 |
| 缓存目录 | `~/.gradle` | 默认 GRADLE_USER_HOME，可挂载 |

**使用 unzip + mv**：Gradle 使用 `.zip` 格式（不支持 `--strip-components`），解压后重命名目录为固定名称。

### PATH 配置

添加 `~/opt/gradle/bin` 到 PATH 环境变量，与现有 Maven 配置模式一致。

## 与现有组件的关系

### 与 Maven

无冲突。Gradle 和 Maven 是独立的构建工具，可以共存。用户可根据项目需求选择使用哪个。

### 与 Android SDK

无冲突。Android SDK 通过 `entrypoint.sh` 在运行时安装，Gradle 在构建阶段预装。两者功能不同：
- Gradle：构建工具
- Android SDK：平台工具（sdkmanager、platform-tools、build-tools）

### 与 JDK

Gradle 9.x 支持 JDK 8~21。当前默认 JDK 8（`JDK_VERSION=8`）完全兼容。用户可通过 `build_args` 同时调整 JDK_VERSION 和 GRADLE_VERSION。

## 可挂载目录汇总

| 目录 | 内容 |
|------|------|
| `~/opt` | Maven、Gradle、Neovim 安装目录 |
| `~/.gradle` | Gradle 缓存（wrapper、依赖） |
| `~/.m2` | Maven 缓存 |
| `/opt/android-sdk` | Android SDK |

## 安装步骤（Dockerfile）

在现有 Maven 安装步骤后添加：

```dockerfile
# 精确安装指定版本的 Gradle (neo 用户)
ARG GRADLE_VERSION=9.4.1
RUN wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -O /tmp/gradle.zip && \
    unzip /tmp/gradle.zip -d ~/opt && \
    mv ~/opt/gradle-${GRADLE_VERSION} ~/opt/gradle && \
    rm /tmp/gradle.zip
```

**注意**：Gradle 使用 `.zip` 格式而非 `.tar.gz`，因此用 `unzip` 而非 `tar`。

## PATH 环境变量更新

将 `~/opt/gradle/bin` 添加到 PATH：

```dockerfile
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/node/bin:/home/${USERNAME}/opt/maven/bin:/home/${USERNAME}/opt/gradle/bin:/home/${USERNAME}/opt/nvim/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
```