# icloud-docker-overlay

Thin Docker image that overlays [epheterson/icloudpy@fix/ios-26.4-auth](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth) onto [`mandarons/icloud-drive:latest`](https://hub.docker.com/r/mandarons/icloud-drive) — restoring 2FA login on iOS 26.4+ trusted devices.

## Why this exists

[`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker) is the canonical container for unified iCloud (Photos + Drive) backup on a NAS. It pins [`icloudpy==0.8.0`](https://github.com/mandarons/icloudpy), which became unusable on iOS 26.4+ in February 2026: the 2FA prompt is sent but no verification code ever arrives on trusted devices — auth stalls forever. See [mandarons/icloud-docker#426](https://github.com/mandarons/icloud-docker/issues/426).

The upstream `icloudpy` library doesn't have the fix yet. I've ported the fix from [icloud_photos_downloader PR #1335](https://github.com/icloud-photos-downloader/icloud_photos_downloader/pull/1335) into [my icloudpy fork](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth) and submitted an upstream PR. While that PR is in review, this overlay container lets you actually run the official mandarons/icloud-docker setup today.

**This is a bridge.** When the upstream `icloudpy` PR merges and `mandarons/icloud-docker` bumps its `requirements.txt`, switch back to vanilla `mandarons/icloud-drive:latest` and retire this overlay.

## Use

Identical to mandarons/icloud-docker — just swap the image:

```yaml
# docker-compose.yml on your NAS
services:
  icloud:
    image: ghcr.io/epheterson/icloud-docker-overlay:latest
    container_name: icloud
    restart: unless-stopped
    volumes:
      - ./config:/config
      - /volume1/ELP NAS/Pictures/iCloud/Eric:/icloud/photos/personal
      - /volume1/ELP NAS/Pictures/iCloud/Shared:/icloud/photos/shared
      - /volume1/ELP NAS/iCloud/Drive:/icloud/drive
    environment:
      - TZ=America/Los_Angeles
```

Use the same [`config.yaml`](https://github.com/mandarons/icloud-docker/blob/main/config.yaml) as upstream documents.

## What's inside

Just two lines on top of mandarons/icloud-drive:

```dockerfile
FROM mandarons/icloud-drive:latest
RUN pip install --upgrade --force-reinstall \
    "icloudpy @ git+https://github.com/epheterson/icloudpy.git@fix/ios-26.4-auth"
```

(Plus a temporary `apk add git` since the base image is Alpine.)

## Status

- **upstream icloudpy PR:** see [epheterson/icloudpy#fix/ios-26.4-auth](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth)
- **upstream icloud-docker issue:** [mandarons/icloud-docker#426](https://github.com/mandarons/icloud-docker/issues/426)
- This overlay will be **archived** once the upstream PR merges + mandarons ships a new container release.

MIT.
