# UniFi OS Server

Runs [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) as a Home Assistant app.

## Configuration

**UOS_SYSTEM_IP**: the hostname (recommended) or IP address devices use for inform. If left empty, the app uses the IP address of Home Assistant's primary network interface.

## Storage

All UniFi OS Server data (`/data`, `/persistent`, `/var/log`, `/srv`, `/var/lib/unifi`, `/var/lib/mongodb`, and `/etc/rabbitmq/ssl`) is kept in the app's config folder (`addon_configs/<slug>`) and included in Home Assistant backups. Uninstalling the app keeps this folder unless you choose to also delete the app's data.

## Ports

| Host port | Usage |
|----|----|
| 11443/tcp | UniFi OS Server GUI/API |
| 8080/tcp | Device and application communication |

Optional UniFi OS Server ports (STUN, discovery, hotspot, syslog, etc.) are disabled. Enable them in the **Network** section of the app's **Configuration** tab.

## Web UI and HSTS

**Open Web UI** opens port 11443 on the same address you use for Home Assistant. UniFi OS Server uses a self-signed certificate, so if you reach Home Assistant through a domain that sends HSTS (for example `ha.example.com`), the browser blocks the page with no way to continue.

To work around it, either:

- Open the web UI by IP address, for example `https://<IP>:11443`.
- Upload a certificate for your domain in UniFi OS Server's own certificate settings.

## Security

systemd inside the container needs `SYS_ADMIN` and AppArmor disabled to mount its filesystems. Supervisor API access is required to detect Home Assistant IP address.
