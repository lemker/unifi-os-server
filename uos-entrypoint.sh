#!/bin/bash

# Persist UOS_UUID env var
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        echo "Setting UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        echo "No UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Spoof a v5 UUID
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        echo "Setting UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

# Read version from package.json and write version string
echo "Setting UOS_SERVER_VERSION to $UOS_SERVER_VERSION"
echo "UOSSERVER.0000000.$UOS_SERVER_VERSION.0000000.000000.0000" > /usr/lib/version
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

# Set UOS_SYSTEM_IP
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    sed -i 's/.*system_ip=.*/system_ip='"$UOS_SYSTEM_IP"'/' /var/lib/unifi/system.properties
fi

# Start systemd
exec /sbin/init