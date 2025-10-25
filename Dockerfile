FROM ghcr.io/lemker/uosserver:0.0.49

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV UOS_SERVER_VERSION="4.3.6"
ENV FIRMWARE_PLATFORM="linux-x64"

# RUN \
#   echo "Install packages" && \
#   apt-get update && \
#   apt-get install -y \
#     uuid-runtime && \
#   apt-get clean

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

ENTRYPOINT ["/root/uos-entrypoint.sh"]