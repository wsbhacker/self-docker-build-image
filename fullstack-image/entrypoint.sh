#!/usr/bin/env bash
set -e

# 确保 ZDOTDIR 存在（支持挂载）
mkdir -p "$ZDOTDIR"

# 初始化 Oh My Zsh（仅当目录不存在时）
if [ ! -d "$ZDOTDIR/ohmyzsh" ]; then
  echo "Installing Oh My Zsh to $ZDOTDIR..."

  export RUNZSH=no
  export CHSH=no

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  # 如果 .zshrc 不存在，移动默认配置
  if [ ! -f "$ZDOTDIR/.zshrc" ]; then
    mv ~/.zshrc "$ZDOTDIR/.zshrc"
  fi
fi

# 检查并安装 Android SDK（仅当 android_dev 环境变量存在时）
if [ -n "${android_dev}" ]; then
  if [ ! -f "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Installing Android SDK..."

  # 确保目录权限
  sudo chown -R "${USERNAME}:${USERNAME}" "${ANDROID_HOME}" 2>/dev/null || true

  # 下载 cmdline-tools
  ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION:-14742923}
  wget https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip \
    -O /tmp/cmdline-tools.zip

  # 解压并安装
  mkdir -p "${ANDROID_HOME}/cmdline-tools"
  unzip /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools"
  mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
  rm /tmp/cmdline-tools.zip

  # 接受许可证
  yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ${SDK_PROXY_ARGS} --licenses > /dev/null 2>&1 || true

  # 安装 SDK 组件
  "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ${SDK_PROXY_ARGS} \
    "platforms;${TARGET_PLATFORM:-android-35}" \
    "build-tools;${BUILD_TOOLS_VERSION:-35.0.0}" \
    "platform-tools"
  fi
fi

exec "$@"
