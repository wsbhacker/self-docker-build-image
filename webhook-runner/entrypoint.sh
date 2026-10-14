#!/bin/sh
# webhook-runner 入口：枚举 $HOOKS_DIR 下所有 *.json 拼成多个 -hooks 参数后启动 webhook
#   （实测 2.8.3：-hooks 不支持目录与 glob，仅支持重复 flag 多文件加载）
# -hotreload：已加载 hooks 文件的内容变化自动重载（如换 secret）；但发现不了新增文件
#   （实测 hotreload 只 watch 启动时传入的文件列表）——加新用例文件后仍需 docker restart
set -eu

HOOKS_DIR="${HOOKS_DIR:-/etc/webhook/hooks.d}"

set --
for f in "$HOOKS_DIR"/*.json; do
    [ -e "$f" ] || continue
    set -- "$@" -hooks "$f"
done

if [ "$#" -eq 0 ]; then
    echo "entrypoint: no hooks found in $HOOKS_DIR, refusing to start empty" >&2
    exit 1
fi

echo "entrypoint: loading hooks from $HOOKS_DIR"
exec webhook "$@" -hotreload -verbose
