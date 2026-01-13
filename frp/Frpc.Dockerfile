# 使用一个轻量的基础镜像
FROM alpine:3.20

# 作者信息
LABEL maintainer="hacker"

# 设置 frp 版本和架构
ARG FRP_VERSION=0.59.0
ARG TARGETARCH

# 根据架构设置对应的下载变量
RUN case ${TARGETARCH} in \
        "amd64") ARCH="amd64" ;; \
        "arm64") ARCH="arm64" ;; \
        "arm/v7") ARCH="arm" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    wget -O frp.tar.gz "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz" && \
    tar -zxvf frp.tar.gz && \
    mv frp_${FRP_VERSION}_linux_${ARCH}/frpc /usr/bin/frpc && \
    chmod +x /usr/bin/frpc && \
    rm -rf frp.tar.gz frp_${FRP_VERSION}_linux_${ARCH}


# 容器启动时运行的命令
# frps 将会加载位于 /etc/frp/frps.toml 的配置文件
CMD ["/usr/bin/frpc", "-c", "/etc/frp/frpc.toml"]
