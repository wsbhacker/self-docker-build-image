FROM python:3.12-slim

ARG TRADINGAGENTS_VERSION=main

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone --depth 1 --branch ${TRADINGAGENTS_VERSION} \
    https://github.com/TauricResearch/TradingAgents.git . \
    && pip install --no-cache-dir . \
    && rm -rf .git

RUN useradd -m appuser \
    && mkdir -p /home/appuser/.tradingagents \
    && chown -R appuser:appuser /home/appuser
USER appuser
WORKDIR /home/appuser

ENTRYPOINT ["sleep", "infinity"]
