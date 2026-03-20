#!/bin/bash

# Persist UOS_UUID env var
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        echo "No UOS_UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Spoof a v5 UUID
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

# Read version from package.json and write version string
echo "Setting UOS_SERVER_VERSION to $UOS_SERVER_VERSION"
echo "UOSSERVER.0000000.$UOS_SERVER_VERSION.0000000.000000.0000" > /usr/lib/version

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" == "amd64" ]; then
    FIRMWARE_PLATFORM=linux-x64
elif [ "$ARCH" == "arm64" ]; then
    FIRMWARE_PLATFORM=arm64
else
    echo "FIRMWARE_PLATFORM not found for $ARCH"
    exit 1
fi

echo "Setting FIRMWARE_PLATFORM to $FIRMWARE_PLATFORM"
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform

# Create eth0 alias to tap0 (requires NET_ADMIN cap & macvlan kernel module loaded on host) 
if [ ! -d "/sys/devices/virtual/net/eth0" ] && [ -d "/sys/devices/virtual/net/tap0" ]; then
    ip link add name eth0 link tap0 type macvlan
    ip link set eth0 up
fi 

# Initialize nginx log dirs
NXINX_LOG_DIR="/var/log/nginx"
if [ ! -d "$NXINX_LOG_DIR" ]; then
    mkdir -p "$NXINX_LOG_DIR"
    chown nginx:nginx "$NXINX_LOG_DIR"
    chmod 755 "$NXINX_LOG_DIR"
fi

# Initialize mongodb log dirs
MONGODB_LOG_DIR="/var/log/mongodb"
if [ ! -d "$MONGODB_LOG_DIR" ]; then
    mkdir -p "$MONGODB_LOG_DIR"
    chown mongodb:mongodb "$MONGODB_LOG_DIR"
    chmod 755 "$MONGODB_LOG_DIR"
fi

# Initialize mongodb lib dirs
MONGODB_LIB_DIR="/var/lib/mongodb"
chown -R mongodb:mongodb "$MONGODB_LIB_DIR"

# Initialize rabbitmq log dirs
RABBITMQ_LOG_DIR="/var/log/rabbitmq"
if [ ! -d "$RABBITMQ_LOG_DIR" ]; then
    mkdir -p "$RABBITMQ_LOG_DIR"
    chown rabbitmq:rabbitmq "$RABBITMQ_LOG_DIR"
    chmod 755 "$RABBITMQ_LOG_DIR"
fi

# Install unifi-access
if [ "$UNIFI_ACCESS" == true ]; then
    mkdir -p /persistent/addons

    curl -LC - -o /persistent/addons/unifi-face-shared-lib_v1.0.6+156.deb \
      https://fw-download.ubnt.com/data/unifi-face-shared-lib/0187-uos-deb11-$ARCH-1.0.6-3fa2b2f6-023a-4fba-8d05-83eee79b0580.deb
    dpkg -i /persistent/addons/unifi-face-shared-lib_v1.0.6+156.deb

    curl -LC - -o /persistent/addons/unifi-user-assets_v0.4.40+529.deb \
      https://fw-download.ubnt.com/data/unifi-user-assets/d7f0-uos-deb11-$ARCH-0.4.40-3bd60132-8ad1-407e-9e39-b54f2339bd10.deb
    dpkg -i /persistent/addons/unifi-user-assets_v0.4.40+529.deb

    curl -LC - -o /persistent/addons/ms_v5.1.44.deb \
      https://fw-download.ubnt.com/data/ms/68b8-uos-deb11-$ARCH-5.1.202-7faf898f-7844-4267-b2c9-e448e98a5bdd.deb
    dpkg -i /persistent/addons/ms_v5.1.44.deb

    apt update && apt install -y coturn
    curl -LC - -o /persistent/addons/unifi-access_v4.1.40+11584.deb \
      https://fw-download.ubnt.com/data/unifi-access/f444-uos-deb11-$ARCH-4.1.40-f4a14bf9-d7a6-4165-abe4-1023afe6ec18.deb
    dpkg -i /persistent/addons/unifi-access_v4.1.40+11584.deb
fi

# Apply Synology patches
SYS_VENDOR="/sys/class/dmi/id/sys_vendor"
if { [ -f "$SYS_VENDOR" ] && grep -q "Synology" "$SYS_VENDOR"; } \
    || [ "${HARDWARE_PLATFORM:-}" = "synology" ]; then

    if [ -n "${HARDWARE_PLATFORM+1}" ]; then
        echo "Setting HARDWARE_PLATFORM to $HARDWARE_PLATFORM"
    else
        echo "Synology hardware found, applying patches..."
    fi

    # Set postgresql overrides
    mkdir -p /etc/systemd/system/postgresql@14-main.service.d
    {
        echo "[Service]"
        echo "PIDFile="
    } > /etc/systemd/system/postgresql@14-main.service.d/override.conf

    # Set rabbitmq overrides
    mkdir -p /etc/systemd/system/rabbitmq-server.service.d
    {
        echo "[Service]"
        echo "Type=simple"
    } > /etc/systemd/system/rabbitmq-server.service.d/override.conf

    # Set ulp-go overrides
    mkdir -p /etc/systemd/system/ulp-go.service.d
    {
        echo "[Service]"
        echo "Type=simple"
    } > /etc/systemd/system/ulp-go.service.d/override.conf

    echo "Synology patches applied!"
fi

# Set UOS_SYSTEM_IP
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    echo "Setting UOS_SYSTEM_IP to $UOS_SYSTEM_IP"
    if [ ! -f "$UNIFI_SYSTEM_PROPERTIES" ]; then
        echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
    else
        if grep -q "^system_ip=.*" "$UNIFI_SYSTEM_PROPERTIES"; then
            sed -i 's/^system_ip=.*/system_ip='"$UOS_SYSTEM_IP"'/' "$UNIFI_SYSTEM_PROPERTIES"
        else
            echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
        fi
    fi
fi

# Start systemd
exec /sbin/init