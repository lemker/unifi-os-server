FROM ghcr.io/lemker/uosserver:0.0.54-multiarch

LABEL org.opencontainers.image.source="https://github.com/lemker/unifi-os-server"

ENV UOS_SERVER_VERSION="5.0.6"
ENV DEBIAN_FRONTEND="noninteractive"

ARG TARGETARCH
ARG UNIFI_VERSION="10.1.89"

STOPSIGNAL SIGRTMIN+3

RUN \
    mkdir -p /tmp/dpkg-hooks; \
    mv /etc/dpkg/dpkg.cfg.d/*ubnt* /tmp/dpkg-hooks/ && \
    apt-get update && \
    apt-get install -y wget apt-transport-https gpg && \
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null && \
    echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list && \
    apt-get update && \
    apt-get install -y temurin-25-jre && \
    UNIFI_DOWNLOAD=$(curl -sX GET "https://fw-update.ubnt.com/api/firmware?filter=eq~~product~~unifi&filter=eq~~platform~~uos-deb11-${TARGETARCH}&filter=eq~~channel~~release&sort=-version" \
        | jq -r "._embedded.firmware[] | select(.version | test(\"v${UNIFI_VERSION}\")) | ._links.data.href") && \
    curl -L -o /tmp/unifi_${UNIFI_VERSION}.deb "${UNIFI_DOWNLOAD}" && \
    dpkg -i /tmp/unifi_${UNIFI_VERSION}.deb && \
    apt autoremove -y && \
    mv /tmp/dpkg-hooks/* /etc/dpkg/dpkg.cfg.d/ && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*; \

COPY uos-entrypoint.sh /root/uos-entrypoint.sh

RUN ["chmod", "+x", "/root/uos-entrypoint.sh"]
ENTRYPOINT ["/root/uos-entrypoint.sh"]