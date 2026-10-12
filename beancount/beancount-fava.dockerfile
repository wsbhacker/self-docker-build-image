# Beancount v3 + Fava 合一镜像，双用途（形态 C）：
#   - 无参数启动   → fava Web 服务 (0.0.0.0:5000, 加载 $LEDGER_FILE)
#   - 带命令启动   → 一次性执行 CLI (bean-check / bean-format / bean-query / fava --help ...)
# 基座显式 pin trixie：官方 python 镜像内 pip 装包同链编译，无 fullstack 那种 OpenSSL 混链问题
FROM python:3.13-slim-trixie

ARG BEANCOUNT_VERSION=3.2.3
ARG FAVA_VERSION=1.30.16

# beancount 与 fava 必须配套升级：fava 依赖其 parser API，历史上 beancount 3.1.0 曾短暂破坏 fava 兼容
# v3 的 C++ 解析核心有 manylinux x86_64/aarch64 预编译 wheel，双架构均为纯 pip 安装
RUN pip install --no-cache-dir \
        "beancount==${BEANCOUNT_VERSION}" \
        "fava==${FAVA_VERSION}"

RUN useradd --create-home --uid 1000 bean \
    && mkdir -p /data \
    && chown bean:bean /data

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER bean
WORKDIR /data

ENV LEDGER_FILE=/data/mmm.beancount \
    FAVA_HOST=0.0.0.0 \
    FAVA_PORT=5000

EXPOSE 5000

# slim 基座无 curl/wget，用 python urllib 自检；urlopen 失败抛异常即退出非 0
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c 'import os, urllib.request; urllib.request.urlopen("http://127.0.0.1:%s/" % os.environ["FAVA_PORT"], timeout=4)'

ENTRYPOINT ["entrypoint.sh"]
