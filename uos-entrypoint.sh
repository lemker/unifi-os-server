#!/bin/bash

# Write the supplied or generated UUID when /data/uos_uuid is absent.
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        echo "No UOS_UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Replace the version digit with 5 without computing a name-based UUID.
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

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
echo "Setting PRODUCT_NAME to $PRODUCT_NAME"
echo "Setting APP_MODEL to $APP_MODEL"
echo "Setting APP_VERSION to $APP_VERSION"

# Write platform metadata from the environment and detected architecture.
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform
echo "$PRODUCT_NAME" > /usr/lib/product_name
echo "$APP_MODEL" > /usr/lib/app_model
# Leave /usr/lib/version unchanged for PROTECT_SERVER.
if [ "$APP_MODEL" != "PROTECT_SERVER" ]; then
    echo "$APP_MODEL.0000000.$APP_VERSION.0000000.000000.0000" > /usr/lib/version
fi

# UOSSERVER's ubnt-tools reads virtual eth0 or tap0 for the serial number.
# Attempt an eth0 fallback when that name is absent. With host networking,
# interface creation and MAC changes affect the host network namespace.
ETH0_MAC_FILE="/data/eth0_mac"
if [ -f "$ETH0_MAC_FILE" ]; then
    ETH0_MAC=$(cat "$ETH0_MAC_FILE")
else
    # Derive a 02-prefixed unicast, locally administered MAC from the UUID text.
    UUID=$(cat /data/uos_uuid 2>/dev/null || echo "$UOS_UUID")
    ETH0_MAC="02:$(echo "$UUID" | md5sum | cut -c1-10 | sed 's/\(.\{2\}\)/\1:/g;s/:$//')"
    echo "$ETH0_MAC" > "$ETH0_MAC_FILE"
fi

if [ ! -d "/sys/class/net/eth0" ]; then
    if [ -d "/sys/class/net/tap0" ]; then
        # Create a macvlan linked to the existing tap0.
        ip link add name eth0 link tap0 type macvlan
        ip link set eth0 up
    else
        # Attempt a dummy interface when neither name exists.
        ip link add name eth0 type dummy 2>/dev/null || \
            echo "Warning: could not create dummy eth0 interface"
    fi
fi

# Attempt MAC assignment when ip reports eth0 as dummy. This does not check
# who created that interface, validate the saved MAC, or report assignment failure.
if ip -d link show dev eth0 2>/dev/null | grep -q ' dummy '; then
    ip link set dev eth0 address "$ETH0_MAC" 2>/dev/null || true
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

# Initialize rabbitmq log dirs
RABBITMQ_LOG_DIR="/var/log/rabbitmq"
if [[ "$APP_MODEL" == "UOSSERVER" && ! -d "$RABBITMQ_LOG_DIR" ]]; then
    mkdir -p "$RABBITMQ_LOG_DIR"
    chown rabbitmq:rabbitmq "$RABBITMQ_LOG_DIR"
    chmod 755 "$RABBITMQ_LOG_DIR"
fi

# Add a unifi-mongodb.service alias for UOSSERVER when absent.
if [[ "$APP_MODEL" == "UOSSERVER" && ! -e /etc/systemd/system/unifi-mongodb.service && ! -L /etc/systemd/system/unifi-mongodb.service ]]; then
    ln -s /lib/systemd/system/mongodb.service /etc/systemd/system/unifi-mongodb.service
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

# Write UOS_SYSTEM_IP to system_ip when the environment variable is set.
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

# Filter this entrypoint's chown calls to ownership mismatches.
# Vendor pre-start scripts still run their own recursive chown commands.
fix_ownership() {
    local dir="$1" user="$2" group="$3"
    if [ -d "$dir" ]; then
        find "$dir" \( ! -user "$user" -o ! -group "$group" \) -exec chown "$user:$group" {} + 2>/dev/null || true
    fi
}

fix_ownership "/var/lib/mongodb" mongodb mongodb
fix_ownership "/usr/lib/ulp-go" ulp-go ulp-go
fix_ownership "/usr/share/unifi-core/app/node_modules/@ubnt" root root

# Write 600-second start-timeout drop-ins. The inspected vendor ulp-go unit
# sets 100 seconds, and the vendor unifi-core unit omits TimeoutStartSec.
mkdir -p /etc/systemd/system/ulp-go.service.d
cat > /etc/systemd/system/ulp-go.service.d/timeout.conf <<'EOF'
[Service]
TimeoutStartSec=600
EOF

mkdir -p /etc/systemd/system/unifi-core.service.d
cat > /etc/systemd/system/unifi-core.service.d/timeout.conf <<'EOF'
[Service]
TimeoutStartSec=600
EOF

# Start systemd
exec /sbin/init
