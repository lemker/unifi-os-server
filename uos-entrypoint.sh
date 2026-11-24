#!/bin/bash

# Home Assistant detection
if [ -f /data/options.json ]; then
    echo "Home Assistant detected, applying setup..."

    # Map app options to environment variables (read before /data is replaced below)
    HA_SYSTEM_IP=$(jq -r '.UOS_SYSTEM_IP // empty' /data/options.json)

    # Fall back to the IP of Home Assistant's primary network interface
    if [ -z "$HA_SYSTEM_IP" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        HA_SYSTEM_IP=$(curl -fsS -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info \
            | jq -r '[.data.interfaces[] | select(.primary)][0].ipv4.address[0] // empty | split("/")[0]')
    fi

    if [ -n "$HA_SYSTEM_IP" ]; then
        export UOS_SYSTEM_IP="$HA_SYSTEM_IP"
    fi

    # Mount read-only cgroup v2
    mount -o remount,rw /sys/fs/cgroup

    # Setup tmpfs mounts
    mount -t tmpfs -o exec tmpfs /tmp
    mkdir -p /var/lib/journal /var/opt/unifi/tmp
    mount -t tmpfs tmpfs /var/lib/journal
    mount -t tmpfs -o size=64m tmpfs /var/opt/unifi/tmp

    # Keep all persistent volumes, including /data, in the app config folder so
    # uninstalling the app keeps or removes them together
    for dir in /data /persistent /var/log /srv /var/lib/unifi /var/lib/mongodb /etc/rabbitmq/ssl; do
        mkdir -p "/config$dir" "$dir"
        mount --bind "/config$dir" "$dir"
    done
    
    echo "Home Assistant setup applied!"
fi

# Expected by /usr/sbin/bootup-invoker
if [ ! -d "/persistent/.config" ]; then
    mkdir -p "/persistent/.config"
fi

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

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" == "amd64" ]; then
    FIRMWARE_PLATFORM=linux-x64
elif [ "$ARCH" == "arm64" ]; then
    FIRMWARE_PLATFORM=linux-arm64
else
    echo "FIRMWARE_PLATFORM not found for $ARCH"
    exit 1
fi

echo "Setting FIRMWARE_PLATFORM to $FIRMWARE_PLATFORM"
echo "Setting PRODUCT_NAME to $PRODUCT_NAME"
echo "Setting APP_MODEL to $APP_MODEL"
echo "Setting APP_VERSION to $APP_VERSION"

# Read version from package.json and write version string
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform
echo "$PRODUCT_NAME" > /usr/lib/product_name
echo "$APP_MODEL" > /usr/lib/app_model

# Protect Server is mounting /usr/lib/version
if [ "$APP_MODEL" != "PROTECT_SERVER" ]; then
    echo "$APP_MODEL.0000000.v$APP_VERSION.0000000.000000.0000" > /usr/lib/version
fi

# Move UniFi Network data from /var/lib/unifi to /data/unifi/data (v5 to v6)
UNIFI_DATA_DIR="/data/unifi/data"
if [[ "$APP_MODEL" == "UOSSERVER" && -d /var/lib/unifi/db && ! -e "$UNIFI_DATA_DIR" ]]; then
    echo "Moving UniFi Network data to $UNIFI_DATA_DIR..."
    mkdir -p /data/unifi
    rm -rf "$UNIFI_DATA_DIR.migrating"

    # Copy to a temporary dir first so an interrupted copy is retried on next start
    if cp -a /var/lib/unifi/. "$UNIFI_DATA_DIR.migrating/" && sync; then
        mv "$UNIFI_DATA_DIR.migrating" "$UNIFI_DATA_DIR"
        find /var/lib/unifi -mindepth 1 -delete
        echo "UniFi Network data moved!"
    else
        echo "Moving UniFi Network data failed!" >&2
        rm -rf "$UNIFI_DATA_DIR.migrating"
    fi
fi

# Migration to Trixie
if [ ! -f /persistent/.migrated60 ]; then
    major=$(cut -d. -f3 /persistent/.config/version 2>/dev/null)
    major="${major#v}"
    migration_ok=1

    if [ -n "$major" ] && [ "$major" -lt 6 ]; then
        echo "Migrating to Debian 13..."

        if [ "$APP_MODEL" == "UOSSERVER" ]; then
            # /var/lib/mongodb was never used (the real db lives in /var/lib/unifi/db), so removing it is cleanup only.
            rm -rf /var/lib/mongodb/*
            chown -hR unifi:unifi /var/lib/unifi
            # Restore java memory limit & remote mongodb connection string.
            # Copy as the unifi user: both paths are unifi-controlled, so a planted symlink
            # must not be followed with root privileges.
            if [ -f /data/unifi/data/env-overrides ]; then
                runuser -u unifi -- cp /data/unifi/data/env-overrides /var/lib/unifi/env-overrides
            fi
        fi

        if [ -d /data/unifi-core/firmware ]; then
            if cp -a /data/unifi-core/firmware/. /persistent/unifi-core/ && sync; then
                rm -rf /data/unifi-core/firmware/
            else
                echo "Copying unifi-core firmware failed!" >&2
                migration_ok=0
            fi
        fi

        chown -hR postgres:postgres /data/postgresql/14/main/
        chown -hR postgres:postgres /var/log/postgresql/
        if [ -d "/data/unifi/data" ]; then
            chown -hR unifi:unifi /data/unifi/
        fi

        # Record installed apps the image doesn't ship, to reinstall once UniFi OS is running
        if [ -d /persistent/dpkg/bullseye/actions ]; then
            rm -f /persistent/.migrated60-apps
            for action in /persistent/dpkg/bullseye/actions/*; do
                app=$(basename "$action")
                if [ "$(cat "$action" 2>/dev/null)" == "unpack" ] \
                    && [ "$(dpkg-query -W -f '${Status}' "$app" 2>/dev/null)" != "install ok installed" ]; then
                    echo "$app" >> /persistent/.migrated60-apps
                fi
            done
        fi

        # Remove Debian 11 package cache
        rm -rf /persistent/dpkg/bullseye

        if [ "$migration_ok" -eq 1 ]; then
            echo "Migrated to Debian 13!"
        fi
    fi

    # Only mark done when every step succeeded, so a partial migration is retried on next boot.
    if [ "$migration_ok" -eq 1 ]; then
        touch /persistent/.migrated60
    fi
fi

# Reinstall apps recorded during the migration from their Debian 13 builds
# Failed apps stay in the list and are retried on next boot
if [ -s /persistent/.migrated60-apps ]; then
    echo "Reinstalling apps after start: $(tr '\n' ' ' < /persistent/.migrated60-apps)"
    cat > /etc/systemd/system/uos-reinstall-apps.service <<'EOF'
[Unit]
Description=Reinstall UniFi OS apps after migration to Debian 13
ConditionPathExists=/persistent/.migrated60-apps
After=unifi-core.service uos-agent.service
Wants=network-online.target

[Service]
Type=oneshot
TimeoutStartSec=30min
ExecStart=/bin/bash -c 'rm -f /persistent/.migrated60-apps.failed; while read -r app; do uos runnable install "$$app" || echo "$$app" >> /persistent/.migrated60-apps.failed; done < /persistent/.migrated60-apps; if [ -f /persistent/.migrated60-apps.failed ]; then mv -f /persistent/.migrated60-apps.failed /persistent/.migrated60-apps; exit 1; fi; rm -f /persistent/.migrated60-apps'

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf ../uos-reinstall-apps.service /etc/systemd/system/multi-user.target.wants/uos-reinstall-apps.service
fi

# Create eth0 alias to tap0 (requires NET_ADMIN cap & macvlan kernel module loaded on host)
if [ ! -d "/sys/devices/virtual/net/eth0" ] && [ -d "/sys/devices/virtual/net/tap0" ]; then
    ip link add name eth0 link tap0 type macvlan
    ip link set eth0 up
fi

# Fix PostgreSQL permissions, bind mounts can come up owned by another user
# /data/postgresql, the version dir, and .configured stay owned by root
for PG_CLUSTER_DIR in /data/postgresql/*/*/; do
    PG_CLUSTER_DIR="${PG_CLUSTER_DIR%/}"
    PG_DATA_DIR="$PG_CLUSTER_DIR/data"
    [ -d "$PG_DATA_DIR" ] || continue

    PG_MODE=$(stat -c %a "$PG_DATA_DIR")
    if [[ "$PG_MODE" != "700" && "$PG_MODE" != "750" ]] \
        || [ -n "$(find "$PG_CLUSTER_DIR" -path "$PG_CLUSTER_DIR/.configured" -prune -o ! -user postgres -print -quit)" ]; then
        echo "Fixing PostgreSQL permissions for $PG_CLUSTER_DIR..."
        chown postgres:postgres "$PG_CLUSTER_DIR"
        find "$PG_CLUSTER_DIR" -mindepth 1 -maxdepth 1 ! -name .configured -exec chown -hR postgres:postgres {} +
        chmod 700 "$PG_DATA_DIR"
    fi
done

# Initialize nginx log dirs
NXINX_LOG_DIR="/var/log/nginx"
if [ ! -d "$NXINX_LOG_DIR" ]; then
    mkdir -p "$NXINX_LOG_DIR"
    chown nginx:nginx "$NXINX_LOG_DIR"
    chmod 755 "$NXINX_LOG_DIR"
fi

# Initialize rabbitmq log dirs
RABBITMQ_LOG_DIR="/var/log/rabbitmq"
if [[ "$APP_MODEL" == "UOSSERVER" && ! -d "$RABBITMQ_LOG_DIR" ]]; then
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
UNIFI_SYSTEM_PROPERTIES="$UNIFI_DATA_DIR/system.properties"
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    echo "Setting UOS_SYSTEM_IP to $UOS_SYSTEM_IP"
    if [ ! -d "$UNIFI_DATA_DIR" ]; then
        install -d -o unifi -g unifi /data/unifi "$UNIFI_DATA_DIR"
    fi
    if [ ! -f "$UNIFI_SYSTEM_PROPERTIES" ]; then
        echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
    else
        if grep -q "^system_ip=.*" "$UNIFI_SYSTEM_PROPERTIES"; then
            sed -i 's/^system_ip=.*/system_ip='"$UOS_SYSTEM_IP"'/' "$UNIFI_SYSTEM_PROPERTIES"
        else
            echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
        fi
    fi
    chown unifi:unifi "$UNIFI_SYSTEM_PROPERTIES"
fi

# Start systemd
exec /sbin/init
