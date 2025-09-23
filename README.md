# UniFi OS Server

Run [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) directly on Docker or Kubernetes.

> The **UniFi OS Server is the new standard for self-hosting UniFi**, replacing the legacy UniFi Network Server. While the Network Server provided basic hosting functionality, it lacked support for key UniFi OS features like Organizations, IdP Integration, or Site Magic SD-WAN. With a fully unified operating system, UniFi OS Server now delivers the same management experience as UniFi-native–including CloudKeys, Cloud Gateways, and Official UniFi Hosting–and is fully compatible with Site Manager for centralized, multi-site control.
>
> <https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi>


⚠️ Please note that UniFi OS Server is currently in early access and might not be stable enough to run in production. The layout of this project and associated resources might change without notice.

# Installation

## Methods

* [Docker Compose](https://github.com/lemker/unifi-os-server/tree/main?tab=readme-ov-file#docker-compose)
* [Kubernetes](https://github.com/lemker/unifi-os-server/tree/main?tab=readme-ov-file#kubernetes)

### Docker Compose

```yaml
---
services:
  unifi-os-server:
    image: ghcr.io/lemker/uosserver:0.0.49
    container_name: uosserver
    privileged: true
    environment:
      - UOS_UUID=
      - UOS_SERVER_VERSION=4.3.5
      - FIRMWARE_PLATFORM=linux-x64
    volumes:
      - /path/to/uosserver/persistent:/persistent
      - /path/to/uosserver/var-log:/var/log
      - /path/to/uosserver/data:/data
      - /path/to/uosserver/srv:/srv
      - /path/to/uosserver/var-lib-unifi:/var/lib/unifi
      - /path/to/uosserver/var-lib-mongodb:/var/lib/mongodb
      - /path/to/uosserver/etc-rabbitmq-ssl:/etc/rabbitmq/ssl
    ports:
      - 11443:443
      - 5005:5005 # Optional
      - 9543:9543 # Optional
      - 6789:6789 # Optional
      - 8080:8080
      - 8443:8443 # Optional
      - 8444:8444 # Optional
      - 3478:3478/udp
      - 5514:5514/udp # Optional
      - 10003:10003/udp
      - 11084:11084 # Optional
      - 5671:5671 # Optional
      - 8880:8880 # Optional
      - 8881:8881 # Optional
      - 8882:8882 # Optional
    restart: unless-stopped
```

### Kubernetes

See [kubernetes.yaml](https://github.com/lemker/unifi-os-server/blob/main/kubernetes.yaml)

Deployment example uses [ingress-nginx](https://github.com/kubernetes/ingress-nginx) for the ingress and [longhorn](https://github.com/longhorn/longhorn) for storage.

Your ingress controller must be modified to accept extra ports. For example, `ingress-nginx` Helm values:

```bash
tcp:
  5005: "unifi/uosserver-rtp-svc:5005" # Optional
  9543: "unifi/uosserver-id-hub-svc:9543" # Optional
  6789: "unifi/uosserver-mobile-speedtest-svc:6789" # Optional
  8080: "unifi/uosserver-communication-svc:8080"
  8443: "unifi/uosserver-network-app-svc:8443" # Optional
  8444: "unifi/uosserver-hotspot-secured-svc:8444" # Optional
  11084: "unifi/uosserver-site-supervisor-svc:11084" # Optional
  5671: "unifi/uosserver-aqmps-svc:5671" # Optional
  8880: "unifi/uosserver-hotspot-redirect-0-svc:8880" # Optional
  8881: "unifi/uosserver-hotspot-redirect-1-svc:8881" # Optional
  8882: "unifi/uosserver-hotspot-redirect-2-svc:8882" # Optional
udp:
  3478: "unifi/uosserver-stun-svc:3478"
  5514: "unifi/uosserver-syslog-svc:5514" # Optional
  10003: "unifi/uosserver-discovery-svc:10003"
```

Helm charts coming soon, once more integrations are added to the upstream container and there is a better understanding of the overall structure.

## Post-Installation Steps

### Fix Directory Permissions


1. Exec into the container and run:

   ```bash
   mkdir /var/log/nginx 
   chown -R nginx:nginx /var/log/nginx
   mkdir /var/log/mongodb
   chown -R mongodb:mongodb /var/log/mongodb
   chown -R mongodb:mongodb /var/lib/mongodb
   ```
2. Restart container

### Check Services

Ensure that all UniFi OS Server services are up and running:

```yaml
service unifi status
service nginx status
service mongodb status
service rabbitmq-server status
```

### Set System IP


1. Exec into container
2. Update `/var/lib/unifi/system.properties`

   ```yaml
   system_ip=xxx.xxx.xxx.xxx
   ```
3. Restart `unifi` service:

   ```bash
   service unifi restart
   ```

# Parameters

## Environment Variables

| Env | Function |
|----|----|
| UOS_UUID | UUID for your Unifi OS Server instance |
| UOS_SERVER_VERSION | Unifi Server OS version (bundled with image) |
| FIRMWARE_PLATFORM | Host firmware platform |

### UOS_UUID

Works with any v5 UUID, is probably only used to differentiate installations when connecting via <https://unifi.ui.com/> or the app.

## Ports

| Protocol | Port | Direction | Usage |
|----|----|----|----|
| TCP | 11443 | Ingress | Unifi OS Server GUI/API |
| TCP | 5005 | ? | RTP (Real-time Transport Protocol) control protocol |
| TCP | 9543 | ? | UniFi Identity Hub |
| TCP | 6789 | Ingress | UniFi mobile speed test |
| TCP | 8080 | Ingress | Device and application communication |
| TCP | 8443 | Ingress | UniFi Network Application GUI/API |
| TCP | 8444 | Ingress | Secure Portal for Hotspot |
| UDP | 3478 | Both | STUN for device adoption and communication *(also required for Remote Management)* |
| UDP | 5514 | Ingress | Remote syslog capture |
| UDP | 10003 | Ingress | Device discovery during adoption |
| TCP | 11084 | Ingress | UniFi Site Supervisor |
| TCP | 5671 | ? | AQMPS |
| TCP | 8880 | Ingress | Hotspot portal redirection (HTTP) |
| TCP | 8881 | Ingress | Hotspot portal redirection (HTTP) |
| TCP | 8882 | Ingress | Hotspot portal redirection (HTTP) |

# Known Issues

* Container runs in `privileged` mode, which gives full access to host kernel, devices, etc. This can probably be tightened up once more integrations are added and there is a better understanding of permission requirements
* Updating UniFi integrations through the UniFi OS Server web interface might not work properly and break UniFi Network or other services.
* Incorrect directory permissions on initial install for NGINX and MongoDB services
