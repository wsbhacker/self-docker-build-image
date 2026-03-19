FROM nvidia/cuda:13.2.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies (Python 3.12 included in Ubuntu 24.04)
RUN apt-get update && apt-get install -y \
    python3 python3-venv \
    git git-lfs unzip g++ curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
# Allow uv to install system packages on Ubuntu 24.04
ENV UV_BREAK_SYSTEM_PACKAGES=1

WORKDIR /opt/CosyVoice

# Clone repository with submodules
RUN git lfs install && \
    git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git .

# Install PyTorch with CUDA 13.0 (native support for Blackwell)
RUN set -x && \
    echo "=== Python version ===" && \
    python3 --version && \
    echo "=== uv version ===" && \
    uv --version && \
    uv pip install --system \
    torch==2.10.0 torchaudio==2.10.0 \
    --index-url https://download.pytorch.org/whl/cu130

# Install other dependencies (exclude torch/torchaudio and old extra-index-url to prevent downgrade)
RUN grep -vE '^torch==|^torchaudio==|^--extra-index-url' requirements.txt > requirements_filtered.txt && \
    uv pip install --system setuptools && \
    uv pip install --system --no-build-isolation -r requirements_filtered.txt && \
    rm requirements_filtered.txt

# Expose port
EXPOSE 50000

# Model directory configuration
# MODEL_ROOT: parent directory for models (default: pretrained_models)
# MODEL_NAME: specific model subdirectory (optional)
# At runtime, model path is constructed as: ${MODEL_ROOT}/${MODEL_NAME}
ENV MODEL_ROOT=pretrained_models

# Entrypoint script to handle environment variables
RUN printf '#!/bin/bash\n\
set -e\n\
MODEL_PATH="${MODEL_ROOT}"\n\
if [ -n "${MODEL_NAME}" ]; then\n\
    MODEL_PATH="${MODEL_ROOT}/${MODEL_NAME}"\n\
fi\n\
exec python3 webui.py --port 50000 --model_dir "${MODEL_PATH}" "$@"\n' \
    > /entrypoint.sh && chmod +x /entrypoint.sh

# Default entrypoint - webui
# Usage examples:
#   docker run ...                                    # uses pretrained_models
#   docker run -e MODEL_NAME=Fun-CosyVoice3-0.5B ...  # uses pretrained_models/Fun-CosyVoice3-0.5B
#   docker run -e MODEL_ROOT=/models -e MODEL_NAME=my-model ...  # uses /models/my-model
#   docker run ... --model_dir /custom/path           # override with custom path
ENTRYPOINT ["/entrypoint.sh"]
CMD []