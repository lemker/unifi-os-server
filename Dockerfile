FROM ghcr.io/lemker/uosserver:fd48e96764d3-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV container="docker"
ENV APP_VERSION="6.0.21"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

RUN ["systemctl", "mask", "getty.target", "getty@.service", "serial-getty@.service", "console-getty.service", "container-getty@.service"]

COPY uos-patch-ui.sh /tmp/uos-patch-ui.sh
RUN ["bash", "-c", "bash /tmp/uos-patch-ui.sh && rm /tmp/uos-patch-ui.sh"]

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]
