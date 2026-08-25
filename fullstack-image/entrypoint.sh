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

# ==========================================
# GUI 桌面支持（WSLg 直通场景）
# 仅当存在 X 显示时初始化: 运行时目录 + DBus 会话总线 + fcitx5 输入法
# 无 DISPLAY 的 CI / 纯终端用法完全不受影响
# ==========================================
if [ -n "${DISPLAY}" ]; then
    # 固定运行时目录与总线地址, 保证后续 docker compose exec 的新会话拿到同一环境
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/gui-session}"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

    # 会话总线未运行则拉起 (GTK IM 模块经 D-Bus 连接 fcitx5)
    if ! [ -S "${DBUS_SESSION_BUS_ADDRESS#unix:path=}" ]; then
        dbus-daemon --session --fork --address="$DBUS_SESSION_BUS_ADDRESS" || true
    fi

    # 预置输入法条目: 全新 fcitx5 默认组仅英文键盘, 无第二输入法可切换;
    # 必须在其首次启动前写入(它退出时会保存内存状态, 反序会被回写覆盖)
    _fcitx_conf="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
    if command -v fcitx5 >/dev/null 2>&1 && [ ! -f "$_fcitx_conf/profile" ]; then
        mkdir -p "$_fcitx_conf"
        cat > "$_fcitx_conf/profile" <<'PROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
PROFILE
    fi
    unset _fcitx_conf

    # fcitx5 必须禁用 wayland 前端: WSLg 的 Weston 拒绝绑定 input-method 协议 (wslg#1430)
    if command -v fcitx5 >/dev/null 2>&1 && ! pgrep -x fcitx5 >/dev/null 2>&1; then
        fcitx5 --disable=wayland -d >/dev/null 2>&1 || true
    fi
fi

exec "$@"
