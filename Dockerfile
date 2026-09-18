FROM alpine:latest

RUN apk add --no-cache \
    strongswan \
    xl2tpd \
    ppp \
    bash \
    curl \
    iproute2 \
    build-base \
    git

# Tải và build microsocks trực tiếp từ source (mất khoảng 3 giây)
RUN git clone https://github.com/rofl0r/microsocks.git /tmp/microsocks && \
    cd /tmp/microsocks && \
    make && \
    cp microsocks /usr/local/bin/ && \
    rm -rf /tmp/microsocks && \
    apk del build-base git

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
