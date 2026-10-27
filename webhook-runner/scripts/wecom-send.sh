#!/bin/sh
# wecom-send：通用企微应用消息发送器（跑在通用 webhook-runner 容器内，uid 1000）
#   与 wecom-notify.sh 的分工：这里不做任何消息拼凑，只接受规范信息并发送；
#   wecom-notify.sh 保留 GitHub push 用例（拼消息那套它自己留着），两边 token/重试逻辑同款，改一处请同步另一处
#   接口约定（与 hook json 的 pass-arguments-to-command 数组顺序一一对应）：
#     $1=content 消息全文（必填）  $2=title 可选（拼正文开头【title】，兼作 ntfy 兜底标题）  $3=to_user 可选（覆盖默认接收人）
#   json 的 name 只是取值路径，与参数名无关——第三方 payload 叫 title+text/subject+body 都行，
#     json 里 name 写第三方字段名、顺序对准 $1/$2/$3 序位即完成适配，脚本零改动
#   门禁由各自 hook json 的 trigger-rule 决定（用户自配）：建议 payload-hmac-sha256 验签，内网信任也可不设
# 部署：拷到 VPS 的 scripts 挂载目录并 chmod +x；hooks json 自配（改 secret 后 600）
#   凭据走 compose 环境变量：默认 WECOM_CORP_ID/WECOM_CORP_SECRET/WECOM_AGENT_ID（secret 是凭据，放 .env 勿进 git）；
#   一机多应用：hook json 经 pass-environment-to-command 传 WECOM_APP_KEY=<hook id>（照 wecom-notify.json 抄），
#     所有 WECOM_* 变量先取 <id大写下划线>_ 同名前缀再回落默认，token 缓存按前缀隔离防 40014 互踩
# 发送失败退出非 0——实测 2.8.3 对命令非 0 仍回 HTTP 200（调用方 delivery 不标红），
#   真实失败信号是 docker logs 的 "error occurred" 行；NTFY_TOPIC 配了则发 ntfy 兜底（唯一推送告警）
set -eu

PREFIX="$(printf '%s' "${WECOM_APP_KEY:-}" | tr 'a-z-' 'A-Z_')"
case "$PREFIX" in *[!A-Z0-9_]*) printf 'wecom-send: WECOM_APP_KEY 含非法字符（仅字母数字-_）：%s\n' "${WECOM_APP_KEY:-}" >&2; exit 1;; esac

wecom_var() { # $1=完整变量名（WECOM_CORP_ID 等）：先 <PREFIX>_$1 再 $1，输出第一个非空值
    v=''
    if [ -n "$PREFIX" ]; then eval "v=\"\${${PREFIX}_$1:-}\""; fi
    if [ -z "$v" ]; then eval "v=\"\${$1:-}\""; fi
    printf '%s' "$v"
}

CORP_ID="$(wecom_var WECOM_CORP_ID)"
CORP_SECRET="$(wecom_var WECOM_CORP_SECRET)"
AGENT_ID="$(wecom_var WECOM_AGENT_ID)"
TO_USER="$(wecom_var WECOM_TO_USER)"
: "${CORP_ID:?需配置 ${PREFIX:+${PREFIX}_}WECOM_CORP_ID=企业ID（管理后台-我的企业-企业信息）}"
: "${CORP_SECRET:?需配置 ${PREFIX:+${PREFIX}_}WECOM_CORP_SECRET=自建应用 Secret（凭据放 .env 勿进 git）}"
: "${AGENT_ID:?需配置 ${PREFIX:+${PREFIX}_}WECOM_AGENT_ID=自建应用 AgentId}"
: "${TO_USER:=@all}" # 接收人 userid（多个用 | 分隔），@all=应用可见范围全员

: "${1:?用法: wecom-send.sh <content> [title] [to_user]}"
CONTENT="$1"
TITLE="${2:-}"
if [ -n "${3:-}" ]; then TO_USER="$3"; fi

# access_token 有效期 7200s 跟 corpid+secret 走；按前缀隔离缓存（gettoken 有频率配额，多应用共享文件会 40014 互踩）
TOKEN_FILE="/tmp/${PREFIX:-WECOM}.token"

notify() { # ntfy 兜底：NTFY_TOPIC 留空则静默跳过；标题剥换行截 100 字节，防 curl 头注入
    [ -n "${NTFY_TOPIC:-}" ] || return 0
    t="$(printf '%s' "$1" | tr -d '\r\n' | head -c 100)"
    curl -fsS --max-time 10 -H "Title: $t" -d "" "${NTFY_SERVER:-https://ntfy.sh}/${NTFY_TOPIC}" >/dev/null || true
}

fetch_token() { # 成功置 TOKEN；返回码 1=企业微信报错 2=curl 报错。缓存剩 300s 内即换新（提前量）
    now=$(date +%s)
    if [ -f "$TOKEN_FILE" ]; then
        read -r expiry cached < "$TOKEN_FILE" || true
        if [ -n "${cached:-}" ] && [ "${expiry:-0}" -gt "$((now + 300))" ]; then
            TOKEN="$cached"
            return 0
        fi
    fi
    RESP="$(curl -fsS --max-time 10 "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}")" || return 2
    PARSED="$(printf '%s' "$RESP" | python3 -c 'import json, sys
d = json.load(sys.stdin)
if d.get("errcode") != 0:
    raise SystemExit(1)
print(d["access_token"], d.get("expires_in", 7200))')" || return 1
    TOKEN="${PARSED%% *}"
    printf '%s %s\n' "$((now + ${PARSED##* }))" "$TOKEN" > "$TOKEN_FILE"
}

send_once() { # 用当前 TOKEN 发 BODY；0=成功 1=errcode!=0（置 ERRCODE）2=curl 报错
    RESP="$(curl -fsS --max-time 10 -H 'Content-Type: application/json' -d "$BODY" \
        "https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=${TOKEN}")" || return 2
    ERRCODE="$(printf '%s' "$RESP" | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(d.get("errcode", -1))
raise SystemExit(0 if d.get("errcode") == 0 else 1)')" || return 1
}

# title 仅用于通知摘要：拼正文开头（企微 text 消息无独立标题字段，手机通知栏摘要取消息前缀）
MSG="${TITLE:+【${TITLE}】
}${CONTENT}"

# 应用消息 text 上限 2048 字节；python 统一做 JSON 转义并截断（600 字符最坏 1800 字节留余量）
BODY="$(python3 -c 'import json, sys
print(json.dumps({"touser": sys.argv[1], "msgtype": "text", "agentid": int(sys.argv[2]),
                  "text": {"content": sys.argv[3][:600]}}, ensure_ascii=False))' \
    "$TO_USER" "$AGENT_ID" "$MSG")"

rc=0
fetch_token || rc=$?
if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 2 ]; then
        notify "wecom-send: 获取 access_token 失败（curl 报错）"
    else
        notify "wecom-send: 获取 access_token 失败：${RESP:-}"
    fi
    exit 1
fi

rc=0
send_once || rc=$?
if [ "$rc" -eq 0 ]; then
    exit 0
fi
if [ "$rc" -eq 2 ]; then
    notify "wecom-send: 应用消息请求失败（curl 报错）"
    exit 1
fi
# 40014/42001=token 失效/过期：token 缓存过期瞬间的正常竞态，清缓存换新 token 重发一次
if [ "${ERRCODE:-}" = "40014" ] || [ "${ERRCODE:-}" = "42001" ]; then
    rm -f "$TOKEN_FILE"
    if fetch_token && send_once; then
        exit 0
    fi
    notify "wecom-send: 应用消息重发仍失败：${RESP:-}"
    exit 1
fi
notify "wecom-send: 应用消息发送失败：${RESP:-}"
exit 1
