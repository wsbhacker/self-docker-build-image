ARG BASE_VERSION=1.8.95
FROM ghcr.io/0xW5B/aktools:${BASE_VERSION}

ARG AKSHARE_VERSION
RUN pip install akshare==${AKSHARE_VERSION} -i https://pypi.org/simple
