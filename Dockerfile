# Pinned: `latest` would silently change the base image under us
FROM alpine:3.24

RUN apk add --no-cache \
    strongswan \
    xl2tpd \
    ppp \
    bash \
    curl \
    iproute2 \
    socat \
    wireguard-tools \
    iptables \
    build-base \
    git

# Tải và build microsocks trực tiếp từ source (mất khoảng 3 giây)
# Pinned to a release tag instead of whatever master holds at build time
RUN git clone --depth 1 --branch v1.0.5 https://github.com/rofl0r/microsocks.git /tmp/microsocks && \
    cd /tmp/microsocks && \
    make && \
    cp microsocks /usr/local/bin/ && \
    rm -rf /tmp/microsocks && \
    apk del build-base git

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
