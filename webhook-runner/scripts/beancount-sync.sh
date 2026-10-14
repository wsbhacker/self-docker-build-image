#!/bin/sh
# beancount-sync：beancount 账本同步用例（跑在通用 webhook-runner 容器内，uid 1000）
#   由 hooks.d/beancount-sync.json 触发：git pull --ff-only → bean-check（容器内有则跑）
#   任一失败发 ntfy 通知并退出非 0（实测 2.8.3 对命令非 0 仍回 200，delivery 不标红——真信号是 docker logs + ntfy）
# 部署：拷到 VPS 的 scripts 挂载目录并 chmod +x；hooks json 拷到 hooks.d（改 secret 后 600）
# 幂等：重复触发只是多 pull 一次空更新；flock 防连续 push 时两个 pull 并发写 .git
set -eu

LEDGER_DIR="${LEDGER_DIR:-/ledger}"
LEDGER_FILE="${LEDGER_FILE:-/ledger/mmm.beancount}"

# 挂载卷的属主若与容器 uid 不一致，git 会拒绝工作（dubious ownership）
git config --global --add safe.directory "$LEDGER_DIR"

# NTFY_TOPIC 留空则静默跳过；NTFY_SERVER 可指向自托管实例（默认公共服 ntfy.sh）
notify() { # notify "标题"
    [ -n "${NTFY_TOPIC:-}" ] || return 0
    curl -fsS --max-time 10 -H "Title: $1" -d "" "${NTFY_SERVER:-https://ntfy.sh}/${NTFY_TOPIC}" >/dev/null || true
}

exec 9>/tmp/beancount-sync.lock
flock 9

# token 注入二选一：环境变量 LEDGER_SYNC_TOKEN（remote 为干净 URL 时）；
# 留空则沿用仓库 remote URL 里已内嵌的 token（git clone https://token@... 的现状）
# shellcheck disable=SC2086  # 需按空白拆分为多个参数
PULL_AUTH=""
if [ -n "${LEDGER_SYNC_TOKEN:-}" ]; then
    PULL_AUTH="-c http.extraheader=Authorization: Bearer ${LEDGER_SYNC_TOKEN}"
fi

if ! git $PULL_AUTH -C "$LEDGER_DIR" pull --ff-only; then
    notify "beancount-sync: git pull 失败"
    exit 1
fi

# 语法校验可选：通用 runner 镜像不预装 beancount（保持零业务绑定），没检测到就跳过
# 需要校验时给 runner 叠一层装 beancount 的变体镜像即可（本脚本无需改）
if command -v bean-check >/dev/null 2>&1; then
    if ! bean-check "$LEDGER_FILE"; then
        notify "beancount-sync: bean-check 未通过（账本语法错误）"
        exit 1
    fi
fi
