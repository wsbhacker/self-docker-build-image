FROM python:3.11-alpine
WORKDIR /app

# 创建非 root 用户
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ddl_worker.py .

# pgrep 依赖 procps 包（Alpine 默认不包含）
RUN apk add --no-cache procps

# 健康检查：每 30s 检查进程是否存在
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep -f ddl_worker.py || exit 1

# 确保 appuser 对 /app 目录有写权限（Python __pycache__ 等）
RUN chown -R appuser:appgroup /app

USER appuser
CMD ["python", "-u", "ddl_worker.py"]
