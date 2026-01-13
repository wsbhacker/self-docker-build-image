# 使用一个轻量的基础镜像
FROM python:3.11-slim

# 作者信息
LABEL maintainer="hacker"

RUN python3 -m venv /app/anki/venv

WORKDIR /app/anki

ENV SYNC_PORT=8080
ENV SYNC_BASE=/app/anki/data

# 设置 anki 版本和架构
ARG ANKI_VERSION=25.9.2

RUN /app/anki/venv/bin/pip install --no-cache-dir anki==${ANKI_VERSION}

EXPOSE $SYNC_PORT

# 容器启动时运行的命令
CMD ["/app/anki/venv/bin/python", "-m", "anki.syncserver"]
