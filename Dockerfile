# Thin overlay over mandarons/icloud-docker that swaps in our patched icloudpy.
#
# Why: mandarons/icloud-drive (the upstream container) pins icloudpy==0.8.0,
# which is broken on iOS 26.4+ — no 2FA push notification arrives, so auth
# stalls forever. See https://github.com/mandarons/icloud-docker/issues/426
# and the icloudpy PR submitted alongside this overlay:
# https://github.com/mandarons/icloudpy/pull/?
#
# This overlay reinstalls icloudpy from the fix branch on top of the official
# image. Drop it when upstream merges the PR and ships a new icloudpy release
# that mandarons/icloud-docker picks up — at that point use mandarons/icloud-drive
# directly.
FROM mandarons/icloud-drive:latest

# Install git (alpine) — needed by pip to pull from a git URL
USER root
RUN apk add --no-cache git \
    && pip install --no-cache-dir --upgrade --force-reinstall \
        "icloudpy @ git+https://github.com/epheterson/icloudpy.git@fix/ios-26.4-auth" \
    && apk del git

# Restore the user the base image runs as (boredazfcuk pattern is `abc`)
USER abc

# Inherit ENTRYPOINT / CMD / WORKDIR / VOLUMES / EXPOSE / HEALTHCHECK
# from the base image — we change nothing else.
