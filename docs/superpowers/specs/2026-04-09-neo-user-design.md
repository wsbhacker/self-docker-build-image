---
name: neo-user-dockerfile
description: 为 fullstack.Dockerfile 创建非 root 用户 neo，用于 Claude Code bypassPermissions 模式
---

# 设计文档：创建 neo 非 root 用户

## 背景

当前 `fullstack-image/fullstack.Dockerfile` 以 root 用户运行容器。用户使用 Claude Code 的 `--dangerously-skip-permissions` (bypassPermissions) 模式时遇到安全限制：

```
--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons
```

因此需要创建一个非 root 用户来使用 bypassPermissions 模式进行开发。

## 目标

创建用户 `neo`（致敬 The Matrix），一个非 root 用户，具备完整的开发环境配置。

## 用户配置

| 项目 | 配置 |
|------|------|
| 用户名 | `neo` |
| UID/GID | 自动分配（不固定） |
| sudo 权限 | 不需要（bypassPermissions 模式不支持 sudo） |
| 主目录 | `/home/neo` |
| 工作目录 | `/home/neo/work` |
| 默认 Shell | `/bin/zsh` |

## Shell 配置

与当前 root 用户保持一致：
- Oh My Zsh
- ys 主题
- zsh-autosuggestions 插件
- zsh-syntax-highlighting 插件
- alias: vim → nvim, vi → nvim

## Dockerfile 改动

在第 8 节（Oh My Zsh 配置）之后添加新节：

```dockerfile
# ==========================================
# 9. 创建 neo 用户（非 root）
# ==========================================
RUN useradd -m -s /bin/zsh neo && \
    # 为 neo 安装 Oh My Zsh (使用 --unattended 非交互模式)
    su - neo -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' && \
    # 安装 zsh 插件 (需要 chown 给 neo 用户)
    git clone https://github.com/zsh-users/zsh-autosuggestions /home/neo/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting /home/neo/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    chown -R neo:neo /home/neo/.oh-my-zsh/custom/plugins && \
    # 配置 .zshrc
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /home/neo/.zshrc && \
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' /home/neo/.zshrc && \
    echo "alias vim='nvim'" >> /home/neo/.zshrc && \
    echo "alias vi='nvim'" >> /home/neo/.zshrc

# ==========================================
# 10. 切换到 neo 用户
# ==========================================
USER neo
RUN mkdir -p /home/neo/work
WORKDIR /home/neo/work
```

**注意事项**：
- git clone 在 root 下执行后需要 `chown -R neo:neo` 将插件目录所有权转给 neo
- Oh My Zsh 安装使用 `su - neo -c` 以 neo 用户身份执行
- `USER neo` 后的所有 RUN 命令都以 neo 用户执行

## 验证方式

```bash
# 构建镜像
docker build -t fullstack-test -f fullstack-image/fullstack.Dockerfile .

# 验证用户
docker run -it fullstack-test whoami
# 期望输出: neo

# 验证工作目录
docker run -it fullstack-test pwd
# 期望输出: /home/neo/work

# 验证 Claude Code bypassPermissions 模式
docker run -it fullstack-test claude --dangerously-skip-permissions
# 期望: 不报 "cannot be used with root/sudo privileges" 错误

# 验证 zsh 配置
docker run -it fullstack-test cat /home/neo/.zshrc
# 期望: 包含 Oh My Zsh + 插件配置
```

## 文件修改清单

| 文件 | 操作 |
|------|------|
| `fullstack-image/fullstack.Dockerfile` | 添加第 9、10 节创建 neo 用户 |

## 指令来源

用户需求：创建非 root 用户用于 Claude Code bypassPermissions 开发模式，用户名需有程序员/极客风格。