FROM nvidia/cuda:12.9.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies and Python 3.10
RUN apt-get update && apt-get install -y \
    software-properties-common \
    git git-lfs unzip g++ curl \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.10 python3.10-venv python3.10-dev \
    && rm -rf /var/lib/apt/lists/*

# Use Python 3.10 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
# Ensure uv uses Python 3.10
ENV UV_PYTHON=/usr/bin/python3.10

WORKDIR /opt/CosyVoice

# Clone repository with submodules
RUN git lfs install && \
    git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git .

# Install PyTorch with CUDA 12.9 using direct wheel URLs (cp310 for cu129)
RUN uv pip install --system \
    https://download.pytorch.org/whl/cu129/torch-2.8.0%2Bcu129-cp310-cp310-linux_x86_64.whl \
    https://download.pytorch.org/whl/cu129/torchaudio-2.8.0%2Bcu129-cp310-cp310-linux_x86_64.whl \
    || (echo "=== PyTorch install failed, checking Python ===" && \
        python3.10 --version && \
        which python3.10 && \
        ls -la /usr/bin/python* && \
        exit 1)

# Install other dependencies (exclude torch/torchaudio and old extra-index-url to prevent downgrade)
RUN grep -vE '^torch==|^torchaudio==|^--extra-index-url' requirements.txt > requirements_filtered.txt && \
    uv pip install --system -r requirements_filtered.txt && \
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
exec python3.10 webui.py --port 50000 --model_dir "${MODEL_PATH}" "$@"\n' \
    > /entrypoint.sh && chmod +x /entrypoint.sh

# Default entrypoint - webui
# Usage examples:
#   docker run ...                                    # uses pretrained_models
#   docker run -e MODEL_NAME=Fun-CosyVoice3-0.5B ...  # uses pretrained_models/Fun-CosyVoice3-0.5B
#   docker run -e MODEL_ROOT=/models -e MODEL_NAME=my-model ...  # uses /models/my-model
#   docker run ... --model_dir /custom/path           # override with custom path
ENTRYPOINT ["/entrypoint.sh"]
CMD []