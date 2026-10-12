#!/bin/sh
# 形态 C 双用途入口：
#   无参数   → 服务模式启动 fava（加载 $LEDGER_FILE）
#   已知命令 → 原样执行（fava --help / bean-check / python / sh ...）
#   其他参数 → 视为账本路径，以该文件启动 fava
set -e

start_fava() {
    # shellcheck disable=SC2086  # FAVA_EXTRA_ARGS 需按空白拆分为多个参数
    exec fava -H "${FAVA_HOST:-0.0.0.0}" -p "${FAVA_PORT:-5000}" ${FAVA_EXTRA_ARGS:-} "$1"
}

case "$1" in
    fava|bean-*|python*|pip*|sh|ash|bash)
        exec "$@"
        ;;
    "")
        start_fava "${LEDGER_FILE:-/data/mmm.beancount}"
        ;;
    *)
        start_fava "$1"
        ;;
esac
