#!/usr/bin/env bash
set -e

# 确保 ZDOTDIR 存在（支持挂载）
mkdir -p "$ZDOTDIR"

# 初始化 Oh My Zsh（仅当目录不存在时）
if [ ! -d "$ZDOTDIR/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh to $ZDOTDIR..."

  export RUNZSH=no
  export CHSH=no

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  # 移动 Oh My Zsh 到 ZDOTDIR
  mv ~/.oh-my-zsh "$ZDOTDIR/.oh-my-zsh"

  # 如果 .zshrc 不存在，移动默认配置
  if [ ! -f "$ZDOTDIR/.zshrc" ]; then
    mv ~/.zshrc "$ZDOTDIR/.zshrc"
  fi
fi

exec "$@"
