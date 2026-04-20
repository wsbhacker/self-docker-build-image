#!/usr/bin/env bash
set -e

# 确保 ZDOTDIR 存在（支持挂载）
mkdir -p "$ZDOTDIR"

# 初始化 Oh My Zsh（仅第一次）
if [ ! -f "$ZDOTDIR/.zshrc" ]; then
  echo "Initializing Oh My Zsh in $ZDOTDIR..."

  export RUNZSH=no
  export CHSH=no

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  # 移动配置到 ZDOTDIR
  mv ~/.zshrc "$ZDOTDIR/.zshrc"
fi

exec "$@"
