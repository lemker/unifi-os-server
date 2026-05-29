FROM ghcr.io/lemker/uosserver:f77bca81ecbf-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV APP_VERSION="5.1.15"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]