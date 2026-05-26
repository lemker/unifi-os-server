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


PGDATA="/data/postgresql"

if [ "$(echo "${SKIP_PGSQL_PERM:-}" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
    if [ -d "$PGDATA" ]; then
        echo "Checking PostgreSQL permissions"

        NEED_FIX=0

        if find "$PGDATA" ! -user postgres -o ! -group postgres \
               -o -type d ! -perm 700 -o -type f ! -perm 600 | grep -q .; then
            echo "Ownership or permission issue detected"
            NEED_FIX=1
        fi

        if [ "$NEED_FIX" -eq 1 ]; then
            echo "Applying correct permissions..."
            find "$PGDATA" -type d -exec chmod 700 {} \;
            find "$PGDATA" -type f -exec chmod 600 {} \;
            chown -R postgres:postgres "$PGDATA"
            systemctl restart postgresql@14-main

            echo -n "Waiting for PostgreSQL to start"
            TIMEOUT=30
            while ! systemctl is-active --quiet postgresql@14-main && [ $TIMEOUT -gt 0 ]; do
                echo -n "."
                sleep 1
                TIMEOUT=$((TIMEOUT-1))
            done

            if systemctl is-active --quiet postgresql@14-main; then
                echo " PostgreSQL is running."
            else
                echo "ERROR: PostgreSQL failed to start"
                journalctl -u postgresql@14-main --no-pager -n 50
            fi
        else
            echo "PostgreSQL permissions are correct."
        fi
    else
        echo "PostgreSQL data directory does not exist, skipping check."
    fi
else
    echo "Skipping PostgreSQL permission check because SKIP_PGSQL_PERM is true"
fi

# Start systemd
exec /sbin/init
