FROM ghcr.io/lemker/uosserver:0.0.54-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV UOS_SERVER_VERSION="5.0.6"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]