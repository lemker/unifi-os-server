#!/usr/bin/env sh

# exit on any error
set -e

if [ "${REQUIRE_AUTH_KEY}" = "true" ] && [ -z "${TS_AUTH_KEY}" ]
then
    echo "TS_AUTH_KEY is required"
    exit 0
fi

# load the kernel module if it exists
if modprobe wireguard 2>/dev/null
then
    modinfo wireguard || true
    dmesg | grep wireguard || true
    export TS_USERSPACE="${TS_USERSPACE:-false}"
fi

mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200

# https://github.com/tailscale/tailscale/blob/main/cmd/containerboot/main.go
exec /usr/local/bin/containerboot
