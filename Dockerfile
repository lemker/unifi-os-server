FROM ghcr.io/lemker/uosserver:0.0.56-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV UOS_SERVER_VERSION="5.0.8"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]