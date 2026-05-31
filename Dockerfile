FROM ghcr.io/lemker/uosserver:f77bca81ecbf-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV APP_VERSION="5.1.15"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh uos-init.sh uos-mount-wrapper.c /root/
COPY uos-init.service /etc/systemd/system/

RUN rm -f /etc/dpkg/dpkg.cfg.d/015-ubnt-dpkg-status /etc/dpkg/dpkg.cfg.d/020-ubnt-dpkg-cache && \
    apt-get update && apt-get install -y --no-install-recommends gcc libc-dev && \
    gcc -shared -fPIC -o /usr/lib/libuos-mount-wrapper.so /root/uos-mount-wrapper.c -ldl && \
    apt-get purge -y gcc libc-dev && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /root/uos-mount-wrapper.c

RUN chmod +x /root/uos-entrypoint.sh /root/uos-init.sh && \
    ln -s /etc/systemd/system/uos-init.service /etc/systemd/system/basic.target.wants/uos-init.service

ENTRYPOINT ["/sbin/init"]
