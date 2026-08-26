#!/usr/bin/env bash
# ============================================
# 探测 ZCode 最新公开版本
# 由两个工作流共用(勿把逻辑内联回 YAML):
#   - .github/workflows/check-fullstack-updates.yml → 取时间戳参与三路 max 比较
#   - .github/workflows/build-fullstack-batch.yml   → 取版本号注入 ZCODE_VERSION build-arg
#
# 背景: CDN 无全局 latest 端点(latest.yml 仅存在于按版本路径下), 官网页面
# 每次发版整体重新生成并硬编码当前版本直连, 故从 changelog SSR 页提取最大
# 版本号。提取必须平台无关: 页面未必然嵌全某版本的 linux-x64 deb 直链
# (实测 3.9.1 就没有), 但 releases/<ver>/<平台>/ 路径一定有。
# 拿到版本号后再去 CDN 确认存在性, 并取该版本 latest.yml 的 releaseDate。
#
# 输出契约:
#   stdout: 可被 eval 的 KEY=value 行
#           (ZCODE_OK / ZCODE_VER / ZCODE_RELEASE_DATE / ZCODE_TS)
#   stderr: 人类可读诊断信息
# 失败语义(fail-safe): 永远 exit 0; 任一环节失败置 ZCODE_OK=0,
#   调用方据此走兜底(batch 不注入→回落 ARG 默认值 / check 记 ts=0 不参与比较)
# ============================================
set -uo pipefail

ZCODE_OK=0
ZCODE_VER=""
ZCODE_RELEASE_DATE=""
ZCODE_TS=0

emit() {
  printf 'ZCODE_OK=%s\nZCODE_VER=%s\nZCODE_RELEASE_DATE=%s\nZCODE_TS=%s\n' \
    "$ZCODE_OK" "$ZCODE_VER" "$ZCODE_RELEASE_DATE" "$ZCODE_TS"
}

VER=$(curl -sS --max-time 30 https://zcode.z.ai/cn/changelog 2>/dev/null | \
  grep -oE 'releases/[0-9]+\.[0-9]+\.[0-9]+/' | \
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1 || true)

if [ -z "$VER" ]; then
  echo "[zcode-latest] changelog 版本提取失败" >&2
  emit
  exit 0
fi

YML=$(mktemp)
HTTP=$(curl -sS -o "$YML" -w '%{http_code}' \
  "https://cdn-zcode.z.ai/zcode/electron/releases/${VER}/linux-x64/latest.yml")
if [ "$HTTP" != "200" ]; then
  rm -f "$YML"
  echo "[zcode-latest] ${VER} 的 linux-x64/latest.yml http=$HTTP" >&2
  emit
  exit 0
fi

ZCODE_VER="$VER"
ZCODE_RELEASE_DATE=$(grep '^releaseDate:' "$YML" | head -1 | cut -d"'" -f2)
ZCODE_TS=$(date -d "$ZCODE_RELEASE_DATE" +%s 2>/dev/null || echo 0)
rm -f "$YML"
ZCODE_OK=1

echo "[zcode-latest] ver=$ZCODE_VER releaseDate=$ZCODE_RELEASE_DATE ts=$ZCODE_TS" >&2
emit
