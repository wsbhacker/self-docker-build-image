#!/usr/bin/env bash
# ============================================
# GUI 桌面应用层安装脚本（构建期，root 执行）
# 由 fullstack.Dockerfile §2.7 调用；版本可被同名环境变量覆盖。
#
# 三部分：
#   1) ZCode 桌面应用 —— "真身换壳"注入沙箱豁免
#   2) Google Chrome —— 桌面应用的浏览器认证闭环
#   3) xdg-open 补丁 —— 修复带引号 Exec 的自定义协议分发
#
# 背景知识（调试实战结论）：
#   - 容器内无 CAP_SYS_ADMIN 且禁非特权 userns → Chromium 系沙箱不可用；
#     ELECTRON_DISABLE_SANDBOX 只对 Electron 有效，独立 Chrome 必须显式 --no-sandbox
#   - docker 默认 /dev/shm 仅 64MB → Chrome 共享内存超限随机 SIGTRAP，
#     需 --disable-dev-shm-usage（compose 里另配 shm_size 双保险）
#   - 应用经 xdg-open/gio 按 desktop 文件绝对路径启动、不走 PATH，
#     故包装器必须落在真实路径上（Chrome 改 /usr/bin 软链、ZCode 用真身换壳）
# ============================================
set -euo pipefail

ZCODE_VERSION="${ZCODE_VERSION:-3.8.1}"
GOOGLE_CHROME_VERSION="${GOOGLE_CHROME_VERSION:-151.0.7922.173-1}"

echo ">>> [1/3] ZCode ${ZCODE_VERSION}"
wget "https://cdn-zcode.z.ai/zcode/electron/releases/${ZCODE_VERSION}/linux-x64/ZCode-${ZCODE_VERSION}-linux-x64.deb" \
    -O /tmp/zcode.deb
apt-get update
apt-get install -y --no-install-recommends /tmp/zcode.deb
rm /tmp/zcode.deb

# 真身换壳：真身改名 zcode.bin，原路径放注入豁免变量的包装器。
# 浏览器认证回调会经 desktop 文件(用户级带引号 Exec)二次拉起本路径，由此自动安全。
chmod 4755 /opt/ZCode/chrome-sandbox
mv /opt/ZCode/zcode /opt/ZCode/zcode.bin
cat > /opt/ZCode/zcode <<'WRAP'
#!/bin/sh
export ELECTRON_DISABLE_SANDBOX=1
exec /opt/ZCode/zcode.bin "$@"
WRAP
chmod 755 /opt/ZCode/zcode
ln -sf /opt/ZCode/zcode /usr/local/bin/zcode

echo ">>> [2/3] Google Chrome ${GOOGLE_CHROME_VERSION}"
# 版本查询: curl -s https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages | grep -A3 'Package: google-chrome-stable$'
wget "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${GOOGLE_CHROME_VERSION}_amd64.deb" \
    -O /tmp/chrome.deb
apt-get install -y --no-install-recommends /tmp/chrome.deb
rm /tmp/chrome.deb

cat > /usr/local/bin/google-chrome <<'WRAP'
#!/bin/sh
exec /opt/google/chrome/chrome --no-sandbox --no-first-run --password-store=basic --disable-dev-shm-usage "$@"
WRAP
chmod 755 /usr/local/bin/google-chrome
ln -sf google-chrome /usr/local/bin/google-chrome-stable
ln -sf /usr/local/bin/google-chrome /usr/bin/google-chrome-stable
printf '[Default Applications]\ntext/html=google-chrome.desktop\nx-scheme-handler/http=google-chrome.desktop\nx-scheme-handler/https=google-chrome.desktop\n' > /etc/xdg/mimeapps.list

echo ">>> [3/3] patch xdg-open"
# Electron 以 Exec="路径" %U 的带引号格式注册用户级协议处理器，而 xdg-open
# 解析 Exec 首词时把引号并入文件名导致 which 失配、静默执行空命令
# ("811: : Permission denied")。三处解析点统一追加去引号。上游修复后可移除。
python3 <<'PYEOF'
p = '/usr/bin/xdg-open'
s = open(p).read()
a = s.replace('| cut -d= -f 2- | first_word`"', '| cut -d= -f 2- | first_word | tr -d \'\"\'`\"')
b = a.replace('| first_word)"', '| first_word | tr -d \'"\')"')
assert a != s and b != a, 'xdg-open pattern mismatch'
open(p, 'w').write(b)
print('xdg-open exec-parse patched')
PYEOF

echo ">>> GUI 应用层安装完成"
