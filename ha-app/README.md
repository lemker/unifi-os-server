# UniFi OS Server

<a href="https://github.com/lemker/unifi-os-server/pkgs/container/unifi-os-server"><img src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fgithub.com%2Flemker%2Funifi-os-server%2Fpkgs%2Fcontainer%2Funifi-os-server&search=(%3Fs)%3Cspan%5B%5E%3E%5D*%3E%5Cs*Total%5Cs%2Bdownloads%5Cs*%3C%2Fspan%3E.*%3F%3Ch3%5B%5E%3E%5D*%3E%5Cs*(%5B0-9%5D%5B0-9.%2C%5D*%5Cs*%5BKM%5D%3F)%5Cs*%3C%2Fh3%3E&replace=%241&logo=github&label=Downloads&cacheSeconds=3600"></a>
<a href="https://github.com/lemker/unifi-os-server/actions/workflows/build-image.yaml"><img src="https://img.shields.io/github/actions/workflow/status/lemker/unifi-os-server/build-image.yaml?logo=githubactions&logoColor=white&label=Actions"></a>

Run [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) directly in Home Assistant.

> The **UniFi OS Server is the new standard for self-hosting UniFi**, replacing the legacy UniFi Network Server. While the Network Server provided basic hosting functionality, it lacked support for key UniFi OS features like Organizations, IdP Integration, or Site Magic SD-WAN. With a fully unified operating system, UniFi OS Server now delivers the same management experience as UniFi-native–including CloudKeys, Cloud Gateways, and Official UniFi Hosting–and is fully compatible with Site Manager for centralized, multi-site control.
>
> <https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi>

# Parameters

## Options

| Environment | Description |
|----|----|
| UOS_SYSTEM_IP | Hostname or IP for UniFi OS Server |

### UOS_SYSTEM_IP

Set UniFi OS Server hostname (recommended) or IP address for inform. To adopt device:

1. SSH into device with username/password: `ubnt`/`ubnt`
2. Set inform address:

   ```bash
   set-inform http://$UOS_SYSTEM_IP:8080/inform
   ```

# Legal

This project is not affiliated with, endorsed by, or supported by Ubiquiti Inc.
UniFi, the UniFi logo, and UniFi OS are trademarks of Ubiquiti Inc. and are used here only to identify the software this project runs.

This project is licensed under the [GNU Affero General Public License v3.0](https://github.com/lemker/unifi-os-server/blob/main/LICENSE). UniFi OS Server itself is proprietary software owned by Ubiquiti Inc. and is subject to its own license terms.
