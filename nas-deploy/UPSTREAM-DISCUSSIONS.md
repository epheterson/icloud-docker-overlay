# Draft discussion posts for mandarons/icloudpy and mandarons/icloud-docker

These are draft GitHub Discussions to post BEFORE submitting the PRs.
They set context so the maintainer isn't surprised when a flood of
focused, individually-reviewable PRs land.

Post each in the **Ideas** or **General** category — whatever the repo
has enabled.

---

## Discussion to post on `mandarons/icloudpy`

**Title:** Two PRs incoming — iOS 26.4 auth fix + Live Photo `.mov` pair surfacing

**Body:**

```markdown
Hi @mandarons — short heads-up that I have two PRs ready against
`icloudpy:main`:

1. **`fix/ios-26.4-auth`** — fixes the 2FA-code-never-arrives auth
   stall on iOS 26.4+ trusted devices (Feb 2026 Apple change). Ports
   the known-working approach from
   icloud-photos-downloader/icloud_photos_downloader#1335 to
   icloudpy's smaller API surface. Live-validated against a real
   Apple ID with an iOS 26.x trusted device. Resolves the auth-side
   half of mandarons/icloud-docker#426.

2. **`feat/live-photos`** — surfaces the existing `resVidComplRes` /
   `resVidMedRes` / `resVidSmallRes` CloudKit fields as
   `live_video_original` / `live_video_medium` / `live_video_small`
   `versions` keys on `PhotoAsset`, parallel to today's
   `original` / `medium` / `small` for the still image. Lets
   downstream callers (mandarons/icloud-docker, etc.) download the
   paired `.mov` for Live Photos by treating it as just another
   version. Backwards-compatible: keys are silently absent on
   non-Live-Photo stills.

Both PRs are independent and individually reviewable. I'll open
both at the same time and link them here. Combined fork at
[`epheterson/icloudpy@combined/all-fixes`](https://github.com/epheterson/icloudpy/tree/combined/all-fixes)
if you want to test them together.

I also maintain `icloud-docker-plus` — a public bridge image built
from these PRs plus the eleven I'm proposing against
mandarons/icloud-docker. Happy to provide more context on the
end-to-end use case if helpful.

Thanks for icloudpy — really nice library to build on.
```

---

## Discussion to post on `mandarons/icloud-docker`

**Title:** Eleven PRs incoming — migration safety, Photos features, web UI, performance fixes

**Body:**

```markdown
Hi @mandarons — heads-up that I have eleven PRs ready against
`icloud-docker:main`. They came out of a real-world migration from
`boredazfcuk/docker-icloudpd` on an 111K-photo iCloud library, plus
production debugging sessions. Each PR is independent (with one
explicit dependency chain noted below) and individually reviewable.

**Order of submission (recommended):**

| PR | Branch | Type | Independent? | Notes |
|----|--------|------|--------------|-------|
| 13 | `fix/test-suite-non-container-hosts` | test infra | ✅ | **Recommend landing FIRST.** Fixes ~20 pre-existing FileNotFoundError failures on macOS / non-container dev hosts. Lets every other PR be reviewed against a green baseline instead of "these 20 failures are pre-existing." Zero behavior change in containers. |
| 3 | `feat/photos-library-destinations` | feature | ✅ | Optional `photos.library_destinations` maps each iCloud photo library to a subdir. Plus a `SharedLibrary` alias for Apple's GUID-named shared zones (e.g. `SharedSync-3C97...`). |
| 4 | `feat/photos-live-photo-pair-download` | feature | requires icloudpy `feat/live-photos` first | Auto-downloads the paired `.mov` for Live Photos when `original` is in `file_sizes`. Closes #199. |
| 5 | `feat/photos-filename-format-simple` | feature | ✅ | Optional `photos.filename_format: simple` produces `IMG_1234.HEIC` instead of the metadata-suffix style. Collision-safe (falls back to suffix on duplicate names). |
| 6 | `feat/photos-preserve-originals-as-bak` | feature | ✅ | Optional `photos.preserve_originals_as_bak: true` writes the untouched original of edited photos as `.original.bak` so it's hidden from Plex/Photos.app/etc. |
| 7 | `feat/dry-run` | feature | needs 3 + 5 for the photos-side `--check-files` walker | `--dry-run` authenticates + summarises, exits without writing. `--check-files N` walks N items per service and reports per-file `would_skip` / `size_mismatch` / `not_found` counts. The recommended pre-flight for any migration. Has soft-dep fallbacks: works on bare main, just reports against mandarons-default paths. |
| 8 | `feat/require-mount-marker` | feature | ✅ | Optional `{drive,photos}.require_mount_marker: true` refuses to sync unless a marker file is present. Ports the boredazfcuk `.mounted` failsafe — protects against silent bind-mount failures dumping iCloud content into a tmpfs. |
| 9 | `feat/web-ui` | feature | ✅ | Optional Flask app on `:8080` (opt-in via `app.web_ui.enabled`). Dashboard + on-device 2FA re-auth flow. No built-in login — designed for Cloudflare/Authelia/Tailscale front-ends. |
| 10 | `feat/persist-keyring` | fix | ✅ | `XDG_DATA_HOME=/config` in entrypoint so the python-keyring file survives container recreation (Watchtower updates, compose down/up, etc.). Eliminates the "re-auth on every recreate" pain. |
| 11 | `fix/drive-package-single-file-bundles` | fix | ✅ | Stops the loud `0 successful, N failed` log noise and per-cycle re-download for Drive package files that libmagic can't identify as archives (iWork .key/.pages, .band, JMG .jmb, etc). Bytes are on disk and usable; treat as success. |
| 12 | `perf/streaming-photo-enumeration` | perf | ✅ | Chunked album traversal in `album_sync_orchestrator`. Bounds peak RSS by `chunk_size` (default 1000) instead of `len(album)`. Kernel-confirmed cgroup OOM at 4 GB on a 111K-photo library before this fix; bounded under 1 GB after. Empirical validation step in the PR description. |

**Two iCloudPy PRs feed this:**

The `requirements.txt` in `icloud-docker` pins icloudpy. Two
companion PRs against `mandarons/icloudpy` are needed for the
iOS 26.4 auth fix (used by all docker PRs) and the Live Photo
pair-download (used by PR 4). Separate discussion in that repo.

**The image is shipping today** as
[`ghcr.io/epheterson/icloud-docker-plus`](https://github.com/epheterson/icloud-docker-plus)
for users who can't wait for upstream review. Combined branch at
[`epheterson/icloud-docker@combined/all-features`](https://github.com/epheterson/icloud-docker/tree/combined/all-features)
if you want to test the whole stack together. The bridge image's
README is intentionally written as "use upstream when these merge"
— no long-term fork ambition here.

Happy to revise / split / squash any of these to match your review
preferences. Will open PRs once you've had a chance to look at the
shape.

Thanks for `mandarons/icloud-docker` — it's the cleanest of the
icloud-docker family and the natural home for this work.
```

---

## When to post

Post these discussions **before** opening any PR. That way:

1. Mandar isn't surprised by a flood of PRs.
2. He has a chance to push back on shape / strategy before code review.
3. The discussions become the canonical thread for tracking the whole
   batch — easier than juggling 13 separate PR comment threads.

Wait ~24h for any response. If silence, proceed with PR opening per
the order in UPSTREAM-PRS.md.

If Mandar pushes back on a PR's approach, revise that PR's branch
before opening it. The combined branch can stay as the operational
reference for `icloud-docker-plus`.
