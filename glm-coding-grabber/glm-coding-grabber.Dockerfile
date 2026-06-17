FROM python:3.11-slim

LABEL maintainer="hacker"

# Install system dependencies for ddddocr (OpenCV, ONNX Runtime) and Chinese fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    libglib2.0-0 \
    libgl1-mesa-glx \
    libsm6 \
    libxrender1 \
    libxext6 \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    fonts-noto-cjk \
    fonts-arphic-uming \
    fonts-arphic-ukai \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone upstream repository and clean up git
ARG GLM_GRABBER_BRANCH=main
RUN git clone --depth 1 --branch ${GLM_GRABBER_BRANCH} \
    https://github.com/Spanky96/glm-coding-grabber.git . \
    && rm -rf .git

# Install Python dependencies
RUN pip install --no-cache-dir -r captcha/requirements.txt

EXPOSE 9898

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:9898/health || exit 1

CMD ["python", "captcha/ddddocr_server_win.py", "--host", "0.0.0.0", "--port", "9898"]
