# UniFi OS Server

Runs [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) as a Home Assistant app.

## Configuration

**UOS_SYSTEM_IP**: the hostname (recommended) or IP address devices use for inform. If left empty, the app uses the IP address of Home Assistant's primary network interface.

## Resource tuning

Optional CPU/RAM tuning (**off by default**, enable it with the **Resource tuning** switch), applied only through systemd drop-ins, environment files and service config (no UniFi code changes). Every file is regenerated on each start, so switching **Resource tuning** off and restarting restores the stock configuration. The same settings work as `UOS_*` environment variables for Docker/Kubernetes users.

In the app's **Configuration** tab these options are grouped under **Reduce Resources**.

| Option | Default | Effect |
|---|---|---|
| Resource tuning | **off** | Master switch for everything below. Turn it on to apply the settings in this table |
| UniFi Network max heap (MB) | 1024 | Stock lets the Java heap grow to **70% of host RAM**, because Home Assistant doesn't set memory limits on apps. This caps it. |
| Return idle Java memory | on | Every 5 min, G1 periodic GC + native heap trim return memory freed after spikes to the host, and the heap shrinks until about 30% of it is free (stock only shrinks above 70% free). Initial heap 128 MB. |
| Disable unused MongoDB | on | Turns the stand-alone `mongodb.service` (port 27017), which has no clients, into a no-op. UniFi Network still runs `systemctl start mongodb` and needs it to succeed, so the unit is overridden rather than masked. UniFi Network runs its own MongoDB on 27117. Only applied while the stock config has `UNIFI_MONGODB_SERVICE_ENABLED=false`. |
| Journal size limit (MB) | 32 | The systemd journal lives in RAM (`/run`) and otherwise grows to about 10% of `/run` |
| Mask housekeeping timers | on | `apt-daily`, `apt-daily-upgrade`, `e2scrub_all` |
| malloc arenas | 2 | `MALLOC_ARENA_MAX` for all services, which limits glibc memory fragmentation |
| RabbitMQ scheduler threads | 1 | Stock starts one scheduler per CPU. One is plenty for a home controller (about 35 MiB saved on a 4-core host; no saving on a 2-core CI runner). 0 restores stock. |
| Extra JVM options | empty | Advanced |

## Comparing on your own install

1. Under **Settings → Devices & services → Home Assistant Supervisor**, open this app's
   device and enable its **CPU percent** and **Memory percent** sensors.
2. Run for a day with **Resource tuning** off (the default), then a day with it on (same version).
3. Compare the history graphs.

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
