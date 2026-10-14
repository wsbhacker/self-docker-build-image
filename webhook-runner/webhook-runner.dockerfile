# webhook-runner：通用 webhook 接收/处理服务
#   职责边界：镜像只是"工具箱"（adnanh/webhook + git + curl + python3），不含任何业务逻辑
#   hook 定义（*.json）与处理脚本（*.sh）全部从宿主机挂载，加新用例 = 往挂载目录丢文件，镜像零改动
#   用例内容源就是本目录的 hooks.d/ 与 scripts/（部署时拷到 VPS 对应挂载点），说明见 README.md
FROM python:3.13-slim-trixie

# 与仓库其他镜像一致的 pin 习惯：webhook 取 GitHub Releases 固定版本（arm64/amd64 均有预编译）
ARG WEBHOOK_VERSION=2.8.3
ARG TARGETARCH
ADD https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-${TARGETARCH}.tar.gz /tmp/webhook.tar.gz

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && tar -xzf /tmp/webhook.tar.gz -C /usr/local/bin --strip-components=1 \
    && rm /tmp/webhook.tar.gz \
    && useradd --create-home --uid 1000 runner

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# uid 1000：与常见宿主机首个用户对齐，挂载卷（git 仓库等）读写权限顺畅
USER runner

# hook 定义目录（每用例一个 json，entrypoint 动态枚举成多个 -hooks 参数）
# 处理脚本目录（execute-command 指向 /hooks/scripts/ 下的挂载脚本）
# 两者及用例工作目录（如账本仓库）均由 compose 挂载
ENV HOOKS_DIR=/etc/webhook/hooks.d \
    SCRIPTS_DIR=/hooks/scripts

ENTRYPOINT ["entrypoint.sh"]
