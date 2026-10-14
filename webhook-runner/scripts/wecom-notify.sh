#!/bin/sh
# wecom-notify：企业微信应用消息通知用例（跑在通用 webhook-runner 容器内，uid 1000）
#   由 hooks.d/wecom-notify.json 触发：拼文本消息 → 取/缓存 access_token → POST 应用消息接口
#   走自建应用（corpid+secret 换 token 发给成员手机），不是群机器人（那个只要一个 URL key、只能发群、限 20 条/分钟）
#   参数由 pass-arguments-to-command 从 GitHub push payload 注入（顺序与 json 一一对应，勿动）：
#     $1 pusher.name  $2 repository.full_name  $3 ref  $4 commits数组  $5 head_commit.message  $6 compare
#   一机多应用约定：hook json 另经 pass-environment-to-command 传 WECOM_APP_KEY=<hook id>（前缀开关，本身不参与前缀回落），
#     所有 WECOM_* 配置变量逐个先取 <id转大写下划线>_ 同名前缀变量、空则回落不带前缀的默认值——
#     如 id=wecom-notify-ci → 先取 WECOM_NOTIFY_CI_WECOM_CORP_ID/_CORP_SECRET/_AGENT_ID（/_TO_USER）再回落 WECOM_*；
#     不传 key 即纯默认，与单应用旧版行为一致
#   发送失败退出非 0——实测 2.8.3 对命令非 0 仍回 HTTP 200（GitHub delivery 不标红），
#   真实失败信号是 docker logs 的 "error occurred" 行；NTFY_TOPIC 配了则发 ntfy 兜底（唯一推送告警）
# 部署：拷到 VPS 的 scripts 挂载目录并 chmod +x；hooks json 拷到 hooks.d（改 secret 后 600）
#   凭据走 compose 环境变量：默认 WECOM_CORP_ID/WECOM_CORP_SECRET/WECOM_AGENT_ID（secret 是凭据，放 .env 勿进 git）；
#   加第二个应用=拷一份 hook json 改 id/secret/APP_KEY + .env 加前缀三件套，脚本复用不用拷
set -eu

PREFIX="$(printf '%s' "${WECOM_APP_KEY:-}" | tr 'a-z-' 'A-Z_')"
case "$PREFIX" in *[!A-Z0-9_]*) printf 'wecom-notify: WECOM_APP_KEY 含非法字符（仅字母数字-_）：%s\n' "${WECOM_APP_KEY:-}" >&2; exit 1;; esac

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

# access_token 有效期 7200s 跟 corpid+secret 走；按前缀隔离缓存（gettoken 有频率配额，多应用共享文件会 40014 互踩）
TOKEN_FILE="/tmp/${PREFIX:-WECOM}.token"

notify() { # ntfy 兜底（与 beancount-sync 同款）：NTFY_TOPIC 留空则静默跳过
    [ -n "${NTFY_TOPIC:-}" ] || return 0
    curl -fsS --max-time 10 -H "Title: $1" -d "" "${NTFY_SERVER:-https://ntfy.sh}/${NTFY_TOPIC}" >/dev/null || true
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

PUSHER="${1:-someone}"
REPO="${2:-unknown/repo}"
BRANCH="${3#refs/heads/}"
# 提交数：引擎参数提取不支持 gjson 的 commits.# 计数（实测 2.8.3 传空串），改传整个数组由 python 数
COUNT="$(python3 -c 'import json, sys
try:
    print(len(json.loads(sys.argv[1])))
except Exception:
    print(0)' "${4:-[]}")"
# 通知里只取提交首行做摘要（多行 commit body 会撑爆手机通知）
SUBJECT="$(printf '%s\n' "${5:-（更新）}" | head -n 1)"
COMPARE="${6:-}"

MSG="${REPO}（${BRANCH}）：${PUSHER} 推送了 ${COUNT} 个提交
${SUBJECT}"
if [ -n "$COMPARE" ]; then
    MSG="$MSG
${COMPARE}"
fi

# 应用消息 text 上限 2048 字节；python 统一做 JSON 转义并截断（600 字符最坏 1800 字节留余量）
BODY="$(python3 -c 'import json, sys
print(json.dumps({"touser": sys.argv[1], "msgtype": "text", "agentid": int(sys.argv[2]),
                  "text": {"content": sys.argv[3][:600]}}, ensure_ascii=False))' \
    "$TO_USER" "$AGENT_ID" "$MSG")"

rc=0
fetch_token || rc=$?
if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 2 ]; then
        notify "wecom-notify: 获取 access_token 失败（curl 报错）"
    else
        notify "wecom-notify: 获取 access_token 失败：${RESP:-}"
    fi
    exit 1
fi

rc=0
send_once || rc=$?
if [ "$rc" -eq 0 ]; then
    exit 0
fi
if [ "$rc" -eq 2 ]; then
    notify "wecom-notify: 应用消息请求失败（curl 报错）"
    exit 1
fi
# 40014/42001=token 失效/过期：token 缓存过期瞬间的正常竞态，清缓存换新 token 重发一次
if [ "${ERRCODE:-}" = "40014" ] || [ "${ERRCODE:-}" = "42001" ]; then
    rm -f "$TOKEN_FILE"
    if fetch_token && send_once; then
        exit 0
    fi
    notify "wecom-notify: 应用消息重发仍失败：${RESP:-}"
    exit 1
fi
notify "wecom-notify: 应用消息发送失败：${RESP:-}"
exit 1
