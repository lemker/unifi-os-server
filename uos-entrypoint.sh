#!/bin/bash
set -euo pipefail

# --------------------------------------------------
# Prevent dpkg from trying to start services in Docker
# (systemd should manage all services instead)
# --------------------------------------------------
ensure_policy_rc_d() {
    printf '#!/bin/sh\nexit 0\n' > /usr/sbin/policy-rc.d
    chmod 0755 /usr/sbin/policy-rc.d
}

# --------------------------------------------------
# Safe directory initializer
# - Creates directory if missing
# - Applies permissions
# - Applies ownership only if user exists
# (avoids failures in container environments)
# --------------------------------------------------
init_dir() {
    local dir="$1"
    local owner="${2:-}"
    local mode="${3:-755}"

    mkdir -p "$dir"
    chmod "$mode" "$dir" || true

    if [ -n "$owner" ] && getent passwd "${owner%%:*}" >/dev/null 2>&1; then
        chown -R "$owner" "$dir" || true
    fi
}

# --------------------------------------------------
# Ensure required runtime directories exist
# (systemd + services expect these at boot)
# --------------------------------------------------
init_runtime_dirs() {
    init_dir /run "" 755
    init_dir /run/lock "" 755
    init_dir /run/dbus "" 755
    init_dir /tmp "" 1777
    init_dir /var/lib/journal "" 755

    init_dir /var/log/nginx nginx:nginx 755
    init_dir /var/log/mongodb mongodb:mongodb 755
    init_dir /var/log/rabbitmq rabbitmq:rabbitmq 755

    init_dir /var/lib/mongodb mongodb:mongodb 755
    init_dir /var/lib/unifi "" 755
}

# --------------------------------------------------
# Apply container safety fixes before original logic
# --------------------------------------------------
ensure_policy_rc_d
init_runtime_dirs

# --------------------------------------------------
# Persist UOS UUID (device identity)
# - Required for UniFi OS identity consistency
# - Generated once, then reused across restarts
# --------------------------------------------------
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        echo "No UOS_UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Convert to v5-style UUID (UniFi expectation)
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

# --------------------------------------------------
# Write UniFi OS version metadata
# - Consumed by UniFi services for platform identity
# --------------------------------------------------
echo "Setting UOS_SERVER_VERSION to $UOS_SERVER_VERSION"
echo "UOSSERVER.0000000.$UOS_SERVER_VERSION.0000000.000000.0000" > /usr/lib/version

# --------------------------------------------------
# Detect architecture → set platform string
# - Required by UniFi binaries to select correct behavior
# --------------------------------------------------
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

# --------------------------------------------------
# Create eth0 alias if running in tap-based environments
# (some UniFi components expect eth0 to exist)
# --------------------------------------------------
if [ ! -d "/sys/devices/virtual/net/eth0" ] && [ -d "/sys/devices/virtual/net/tap0" ]; then
    ip link add name eth0 link tap0 type macvlan || true
    ip link set eth0 up || true
fi

# --------------------------------------------------
# Synology compatibility patches
# - Adjusts systemd unit behavior for Synology environments
# - Prevents service startup issues on that platform
# --------------------------------------------------
SYS_VENDOR="/sys/class/dmi/id/sys_vendor"
if { [ -f "$SYS_VENDOR" ] && grep -q "Synology" "$SYS_VENDOR"; } \
    || [ "${HARDWARE_PLATFORM:-}" = "synology" ]; then

    if [ -n "${HARDWARE_PLATFORM+1}" ]; then
        echo "Setting HARDWARE_PLATFORM to $HARDWARE_PLATFORM"
    else
        echo "Synology hardware found, applying patches..."
    fi

    # PostgreSQL override (fix PID handling)
    mkdir -p /etc/systemd/system/postgresql@14-main.service.d
    echo -e "[Service]\nPIDFile=" > /etc/systemd/system/postgresql@14-main.service.d/override.conf

    # RabbitMQ override (simplify service type)
    mkdir -p /etc/systemd/system/rabbitmq-server.service.d
    echo -e "[Service]\nType=simple" > /etc/systemd/system/rabbitmq-server.service.d/override.conf

    # ULP service override
    mkdir -p /etc/systemd/system/ulp-go.service.d
    echo -e "[Service]\nType=simple" > /etc/systemd/system/ulp-go.service.d/override.conf

    echo "Synology patches applied!"
fi

# --------------------------------------------------
# Optional: force UniFi system IP
# - Writes/updates system.properties
# - Used for controller self-advertisement
# --------------------------------------------------
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    echo "Setting UOS_SYSTEM_IP to $UOS_SYSTEM_IP"

    mkdir -p "$(dirname "$UNIFI_SYSTEM_PROPERTIES")"

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

# --------------------------------------------------
# Start systemd (PID 1)
# - All services are managed from here
# --------------------------------------------------
exec /sbin/init
