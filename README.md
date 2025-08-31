# UniFi OS Server

Run [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) directly on Docker or Kubernetes.

> The **UniFi OS Server is the new standard for self-hosting UniFi**, replacing the legacy UniFi Network Server. While the Network Server provided basic hosting functionality, it lacked support for key UniFi OS features like Organizations, IdP Integration, or Site Magic SD-WAN. With a fully unified operating system, UniFi OS Server now delivers the same management experience as UniFi-native–including CloudKeys, Cloud Gateways, and Official UniFi Hosting–and is fully compatible with Site Manager for centralized, multi-site control.
>
> <https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi>


⚠️ Please note that UniFi OS Server is currently in early access and might not be stable enough to run in production. The layout of this project and associated resources might change without notice. ⚠️

# Installation

## Methods

* Docker Compose (not tested)
* Kubernetes (recommended)

### Docker Compose

Generate a UUID for your instance and set the environment variable `UOS_UUID`

```yaml
---
services:
  unifi-network-application:
    image: ghcr.io/lemker/uosserver:0.0.47
    container_name: uosserver
    environment:
      - TZ=Etc/UTC
      - UOS_UUID=
      - UOS_SERVER_VERSION=4.3.4
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
      - 5005:5005
      - 9543:9543
      - 6789:6789 
      - 8080:8080
      - 8443:8443
      - 8444:8444
      - 3478:3478/udp
      - 5514:5514/udp
      - 10003:10003/udp
      - 5671:5671
      - 8880:8880
      - 8881:8881
      - 8882:8882
    cap_add:
    - NET_RAW
    - NET_ADMIN
    restart: unless-stopped
```

### Kubernetes

Please see [kubernetes.yaml](https://github.com/lemker/unifi-os-server/blob/main/kubernetes.yaml)

Generate a UUID for your instance and set the environment variable `UOS_UUID`. Deployment example uses [ingress-nginx](https://github.com/kubernetes/ingress-nginx) for the ingress and [longhorn](https://github.com/longhorn/longhorn) for storage.

Helm charts coming soon, once more integrations are added to the upstream container and there is a better understanding of the overall structure.

## Post-Installation Steps

### Fix Directory Permissions

Exec into the container and run:

```bash
mkdir /var/log/nginx
chown -R nginx:nginx /var/log/nginx
chown -R mongodb:mongodb /var/lib/mongodb
mkdir /var/log/mongodb
chown -R mongodb:mongodb /var/log/mongodb
```

### Disable Redirect for Domains

If using a domain to access the UniFi Server OS web interface like `https://unifi.example.com`, disable the internal redirect:


1. Exec into container
2. Edit `/data/unifi-core/config/http/site-setup.conf` and comment out the following block:

   ```bash
   if ($host !~* ^(unifi|localhost|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|\[[a-f0-9:]+\])$) {
       return 302 $scheme://unifi;
   }
   ```
3. Reload config:

   ```yaml
   service nginx reload
   ```

### Check Services

Ensure that all UniFi OS Server services are up and running:

```yaml
service unifi status
service nginx status
service mongodb status
service service rabbitmq-server status
```

# Known Issues

* Container runs in `privileged` mode, which gives full access to host kernel, devices, etc. This can probably be tightened up once more integrations are added and there is a better understanding of permission requirements
* Updating UniFi integrations through the UniFi OS Server web interface might not work properly and break UniFi Network or other services
* Incorrect directory permissions on initial install for NGINX and MongoDB services
* Accessing the web interface with a domain name is blocked due to local IP check on initial install


