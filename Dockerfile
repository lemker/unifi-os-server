FROM ghcr.io/lemker/uosserver:0.0.54-multiarch

ARG TARGETARCH
LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV UOS_SERVER_VERSION="5.0.6"
ENV DEBIAN_FRONTEND="noninteractive"

STOPSIGNAL SIGRTMIN+3

RUN \
    mkdir -p /tmp/dpkg-hooks; \
    mv /etc/dpkg/dpkg.cfg.d/*ubnt* /tmp/dpkg-hooks/ && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        coturn && \
    curl -L -o /tmp/unifi-face-shared-lib.deb \
        "https://fw-download.ubnt.com/data/unifi-face-shared-lib/0187-uos-deb11-${TARGETARCH}-1.0.6-3fa2b2f6-023a-4fba-8d05-83eee79b0580.deb" && \
    curl -L -o /tmp/unifi-user-assets.deb \
      "https://fw-download.ubnt.com/data/unifi-user-assets/d7f0-uos-deb11-${TARGETARCH}-0.4.40-3bd60132-8ad1-407e-9e39-b54f2339bd10.deb" && \
    curl -LC - -o /tmp/ms.deb \
      "https://fw-download.ubnt.com/data/ms/68b8-uos-deb11-${TARGETARCH}-5.1.202-7faf898f-7844-4267-b2c9-e448e98a5bdd.deb" && \
    curl -LC - -o /tmp/unifi-access.deb \
      "https://fw-download.ubnt.com/data/unifi-access/f444-uos-deb11-${TARGETARCH}-4.1.40-f4a14bf9-d7a6-4165-abe4-1023afe6ec18.deb" && \
    dpkg -i \
        /tmp/unifi-face-shared-lib.deb \
        /tmp/unifi-user-assets.deb \
        /tmp/ms.deb \
        /tmp/unifi-access.deb && \
    mv /tmp/dpkg-hooks/* /etc/dpkg/dpkg.cfg.d/ && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*    

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]