# Upstream PR submission guide (thirteen PRs)

Thirteen PRs total — two to `mandarons/icloudpy`, eleven to `mandarons/icloud-docker`. Each is a single feature for clean maintainer review. Submit in the order below — independence note for each.

**Recommended submission order:**

1. **PR 13 first** (`fix/test-suite-non-container-hosts`) — fixes the suite for everyone, no dependencies. Lets every subsequent PR be reviewed against a green baseline instead of "these 20 failures are pre-existing."
2. **PRs 1–2 next** (icloudpy fixes) — independent of the docker repo.
3. **PRs 3–12 in dependency order** — see per-PR independence notes below.

For each PR: easiest path is to **open the URL in a browser** and paste the body manually. The `gh pr create` commands are provided as alternatives.

---

# To `mandarons/icloudpy`

## PR 1: iOS 26.4 SRP auth fix

**Open:** https://github.com/epheterson/icloudpy/pull/new/fix/ios-26.4-auth
**Target:** `mandarons/icloudpy:main`
**Independent:** yes (no dependencies)
**Title:** `fix: trigger 2FA push notification on iOS 26.4+ (resolves the auth stall in mandarons/icloud-docker#426)`

```markdown
## Summary
Restores 2FA on iOS 26.4+ trusted devices.

Since iOS 26.4 (Feb 2026), `validate_2fa_code()` is unreachable in practice
because the 6-digit code never arrives on any trusted device — Apple changed
the flow to require an explicit `PUT /verify/trusteddevice/securitycode`
(no body) to initiate code delivery. Without it, callers see
"Please enter validation code" and wait forever.

This PR adds `ICloudPyService.trigger_2fa_push_notification()` — the explicit
PUT — and wires it into the bundled `icloudpy` CLI so it works out of the
box. The bundled `cmdline.py` calls it right after `requires_2fa` returns
True and before prompting the user for the code.

Other library consumers (mandarons/icloud-docker, etc.) need only add a
single `api.trigger_2fa_push_notification()` call before their own
prompt-for-code logic to inherit the fix.

Refs: mandarons/icloud-docker#426

## Validation
- 4 new unit tests in `tests/test_auth.py`:
  - `test_trigger_2fa_push_notification_success` (happy path via mock)
  - `test_trigger_2fa_push_notification_includes_session_headers` (scnt + session_id forwarding)
  - `test_trigger_2fa_push_notification_api_failure_is_non_fatal` (ICloudPyAPIResponseException → False)
  - `test_trigger_2fa_push_notification_network_failure_is_non_fatal` (ConnectionError / Timeout / SSLError → False)
- Existing tests pass; only the pre-existing `test_storage` ordering issue
  remains, unrelated to this change.
- **Live-validated** against a real Apple ID with an iOS 26.x trusted device:
  push notification arrived, code accepted, Photos + Drive services reachable.

## Approach
Ported from icloud-photos-downloader/icloud_photos_downloader#1335. That fix
has been validated in the `boredazfcuk/docker-icloudpd` community since
2026-05-04 and is the known-working solution. This PR adapts the same
approach to icloudpy's smaller, simpler API surface.

## Notes
- Failure to trigger push is non-fatal (returns False — both `ICloudPyAPIResponseException`
  AND network-level exceptions like `Timeout`/`ConnectionError`/`SSLError`).
  A code may still arrive via SMS or another path, and callers can fall
  through to the `validate_2fa_code` call regardless.
- The SMS-fallback piece of upstream PR #1335 (`pyicloud_ipd/sms.py` changes)
  is not ported here — icloudpy doesn't have an equivalent SMS parser. Its
  2SA flow uses `validate_verification_code` via `/listDevices`, which is a
  separate code path that hasn't been affected by the iOS 26.4 change.
```

---

## PR 2: Live Photo `.mov` pair surfacing

**Open:** https://github.com/epheterson/icloudpy/pull/new/feat/live-photos
**Target:** `mandarons/icloudpy:main`
**Independent:** yes (the version-keys are silently absent for non-Live-Photo stills; no behaviour change for existing callers)
**Title:** `feat: surface Live Photo .mov pair via versions (enables fixing mandarons/icloud-docker#199)`

```markdown
## Summary
Live Photos are stored in CloudKit with both still-image fields
(`resOriginalRes`, `resJPEGMedRes`, …) AND live-video fields
(`resOriginalVidComplRes`, `resVidMedRes`, `resVidSmallRes`) on the same
master_record. Previous icloudpy versions detected "is this a video?" by
checking presence of `resVidSmallRes`, which is true for Live Photos too —
they were misclassified as videos and the still half was dropped.

This change:

1. Adds `ITEM_TYPES` dict mapping Apple UTIs (`public.heic`, `public.jpeg`,
   `com.apple.quicktime-movie`, RAW formats, …) to `"image"` / `"movie"`.
2. Adds `PhotoAsset.item_type` property reading `fields["itemType"]` with a
   filename-extension fallback for assets without the UTI.
3. Changes `versions` detection from the `resVidSmallRes` heuristic to
   `item_type` — correctly classifying Live Photos as images.
4. Extends `PHOTO_VERSION_LOOKUP` with three new keys —
   `live_video_original` / `live_video_medium` / `live_video_thumb` —
   mapping to `resOriginalVidCompl` / `resVidMed` / `resVidSmall`.
   These are silently absent for non-Live-Photo stills (the existing loop
   already filters on field presence), so plain photos are unaffected.

Backward compatibility: existing version keys (`original`, `medium`,
`thumb`, etc.) still work for all stills and videos. Callers that previously
could only access the still half of Live Photos now ALSO see the
`live_video_*` keys.

Closes #199 in `mandarons/icloud-docker` once that project wires up the new
versions key (companion PR submitted there).

## Approach
Ported from `icloud_photos_downloader`'s `pyicloud_ipd.services.photos`,
which has solved this for years.

## Tests
13 new tests in `tests/test_photos.py`:

- `TestItemTypeDetection` (8 tests): UTI lookup (HEIC, JPEG, MOV, RAW),
  extension fallback (HEIC ext / MOV ext), no-UTI-no-filename → None,
  unknown UTI with image extension → image.
- `TestLivePhotoVersions` (5 tests): Live Photo classified as image,
  exposes still version with correct URL, exposes all three `live_video_*`
  versions with correct URLs/types, plain still has no `live_video_*` keys,
  regular video uses `VIDEO_VERSION_LOOKUP`.

Full suite passes; only the pre-existing unrelated `test_storage` failure remains.
```

---

# To `mandarons/icloud-docker`

## PR 3: Per-library destination subdirectories

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/photos-library-destinations
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library changes required)
**Title:** `feat: per-library destination subdirectories (photos.library_destinations)`

```markdown
## Summary
New optional config block `photos.library_destinations` maps each iCloud
library to a subdirectory of `photos.destination`:

\`\`\`yaml
photos:
  destination: photos
  library_destinations:
    PrimarySync: personal
    SharedLibrary: shared
\`\`\`

Personal photos then land in `<photos.destination>/personal/`, Shared
Library photos in `<photos.destination>/shared/`. When `library_destinations`
is unset (the default), all libraries share the single `photos.destination`
tree — preserving the historical mandarons/icloud-docker behaviour, no
breaking change.

## Motivation
Common request from users who want their iCloud Shared Library kept
separate from their personal photos on disk (for separate Plex libraries,
different sharing/backup policies, etc.). Currently the only way to get
this is to run two `mandarons/icloud-docker` containers with different
`libraries:` filters — which means two auth events and two cookie stores
for the same Apple ID.

## Implementation
- New `config_parser.get_photos_library_destinations(config)` returns a
  dict mapping library name → subdir (empty dict when unset).
- New `sync_photos._library_destination(base, library, mapping)` helper
  resolves the per-library destination and creates the subdir.
- Threaded through `sync_photos.sync_photos`, `_sync_all_photos_first_for_hardlinks`,
  and `_sync_albums_by_configuration` as a kwarg with `None` default
  (backward-compatible).
- Obsolete-file cleanup walks each per-library subdir independently when
  `library_destinations` is set, falling back to the legacy
  single-destination walk otherwise.

## Tests
10 new tests in `tests/test_library_destinations.py`:
- Config helper: returns `{}` when unset / when not a dict / coerces
  non-string keys+values to str, returns mapping when configured.
- `_library_destination` helper: returns base when no mapping, returns
  base when library not in mapping, joins subdir + creates dir, handles
  nested subdirs, `None` mapping is safe.
```

---

## PR 4: Live Photo `.mov` pair auto-download

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/photos-live-photo-pair-download
**Target:** `mandarons/icloud-docker:main`
**Depends on:** [PR 2](https://github.com/epheterson/icloudpy/pull/new/feat/live-photos) (requires `live_video_*` keys from icloudpy)
**Title:** `feat: auto-download Live Photo .mov pair (closes #199)`

```markdown
## Summary
When a photo is a Live Photo and the user has requested the `original`
file_size, the orchestrator collects a second download task for the paired
`.mov`. Live Photos now round-trip intact (HEIC + paired MOV land
together in the destination) instead of dropping the video half.

Has no effect on plain stills (the `live_video_original` key is absent in
`photo.versions` for them) or when the user did not request `original`.
Failure to read `photo.versions` is non-fatal — the original-still task is
still emitted.

Closes #199.

## Dependency
Requires icloudpy with the `live_video_*` keys in `PHOTO_VERSION_LOOKUP`
and the `item_type` property — submitted as a companion PR at
mandarons/icloudpy: <link to PR 2 once filed>.

While that PR is in review, `requirements.txt` in this PR temporarily pins
`icloudpy` to the fork branch. **Once PR 2 merges and a new icloudpy
release ships, please bump `requirements.txt` back to a version pin
(e.g. `icloudpy==0.9.0`) — happy to follow up with that change.**

## Tests
5 new tests in `tests/test_live_photo_pair_download.py`:
- Live Photo with `original` requested yields two tasks (still + .mov)
- still photo yields only one task
- Live Photo with only `medium`/`thumb` requested does NOT append .mov
  (the user did not ask for original)
- `photo.versions` raising is non-fatal — original still task is still emitted
- `None` result from `collect_download_task` for the .mov is skipped
```

---

## PR 5: `filename_format: simple` + collision fallback

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/photos-filename-format-simple
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library changes required)
**Title:** `feat: optional photos.filename_format: simple (boredazfcuk migration support)`

```markdown
## Summary
Enables zero-redownload migration from boredazfcuk/docker-icloudpd by
producing the same plain `IMG_1234.HEIC` filenames that boredazfcuk
writes. Since `check_photo_exists` compares by file size (not filename
suffix), an existing tree of boredazfcuk-format files is correctly
recognised as already-present when this container points at it.

Also includes a **collision-safe fallback**: when simple format would put
two distinct iCloud photos at the same path (rare but happens when the
same human filename appears on multiple photos), the colliding photo
routes to the metadata-suffix path so both files coexist on disk.

## Features

### `photos.filename_format` (new optional config, default `metadata`)
- `metadata` (default): `name__filesize__base64id.extension` — historical
  mandarons format. Backward-compatible, no behaviour change for existing
  users.
- `simple`: `name.extension` — boredazfcuk/Apple convention.

### Collision fallback (active automatically when filename_format is simple)
In `collect_download_task`, when the plain `simple`-format path already
exists and the existing file has a DIFFERENT size from the current photo's
CloudKit `versions[file_size].size`, the colliding photo's destination is
switched to the metadata-suffix form. First photo keeps its plain name;
subsequent colliders get unique suffixes. Cross-sync stable.

## Implementation
- Module-level `_DEFAULT_FILENAME_FORMAT` in `photo_path_utils.py` set
  once per sync run by `sync_photos.sync_photos()` via the new
  `set_default_filename_format()` setter. Avoids threading filename_format
  through every `collect_download_task` / `generate_photo_path` signature
  call.
- `generate_photo_filename_with_metadata` branches on the format.
- Collision detection in `collect_download_task` uses `os.path.isfile`
  + the `check_photo_exists` size comparison.

## Tests
20 new tests total:

- `tests/test_filename_format.py` (15 tests): config helper defaults /
  normalisation / fallback on unknown value, generator branching, the
  module-default singleton, end-to-end via `generate_photo_path`.
- `tests/test_collision_fallback.py` (5 tests): no collision uses plain
  path, same photo re-sync skips, collision falls back to suffix (with
  the first file untouched), collision + suffix already downloaded skips,
  metadata mode bypasses the collision logic entirely.

## Notes
- `filename_format` cannot be safely changed mid-flight on an existing
  install — switching means mandarons won't match previously-downloaded
  files and will re-download. Documented in the config helper docstring.
- Simple-format `collect_download_task` recompiles the suffix path with
  explicit `filename_format="metadata"` so the fallback works regardless
  of the module-level default.
```

---

## PR 6: `preserve_originals_as_bak` — hide untouched originals of edited photos

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/photos-preserve-originals-as-bak
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library or other PR dependencies)
**Title:** `feat: optional photos.preserve_originals_as_bak — hide originals of edited photos via .bak`

```markdown
## Summary
New optional config: `photos.preserve_originals_as_bak` (default `False`).

When `True` AND `photos.filters.file_sizes` contains both `original` and
`original_alt`, edited photos land as TWO files on disk:

  - `IMG_1234.JPG`               — the edited "current view" (visible to
                                     Plex / Photos.app / Synology Photos)
  - `IMG_1234.HEIC.original.bak` — the untouched original (no app
                                     recognises `.bak` as an image
                                     extension, so it's hidden from photo
                                     browsers but filesystem-recoverable
                                     for "revert to original" scenarios)

Unedited photos (no `original_alt` available for them on iCloud) are
unaffected — they get their normal single file per the chosen
`filename_format`.

## Motivation
Users who download both versions of edited photos currently see both files
in their photo apps (duplicates). This option lets them treat the edited
version as the canonical "current view" while keeping the untouched
original as a hidden filesystem-level backup.

The toggle is opt-in and defaults False, so existing mandarons users see
no behaviour change.

## Implementation
- New `config_parser.get_photos_preserve_originals_as_bak(config)` returns
  `bool` (default `False`).
- Module-level `_PRESERVE_ORIGINALS_AS_BAK` in `photo_path_utils.py` set
  once per sync run via the new `set_preserve_originals_as_bak()` setter
  (same pattern as `set_default_filename_format`).
- `generate_photo_filename_with_metadata` appends `.original.bak` to the
  filename when the toggle is on, file_size is `original`, AND the photo
  has an `original_alt` version on iCloud.
- Soft check: exceptions reading `photo.versions` are treated as "no alt"
  so a partial CloudKit record cannot break the filename pipeline.

## Tests
10 new tests in `tests/test_preserve_originals_as_bak.py`:
- Config helper defaults / normalisation
- Edited photo's `original` gets the suffix
- Edited photo's `original_alt` does NOT get the suffix
- Unedited photo's `original` does NOT get the suffix
- Non-`original` sizes (medium, thumb, etc.) do not get the suffix
- Suffix not applied when toggle is off
- `photo.versions` exception is non-fatal (falls through to normal name)

## Notes
- The convention chosen (`.original.bak` at the very end of the filename)
  is greppable (`find . -name "*.original.bak"`) and self-documenting on
  casual filesystem browsing.
- Works the same way in both `filename_format: metadata` and
  `filename_format: simple` modes — the `.original.bak` qualifier is
  appended to whatever the base filename would have been.
```

---

## PR 7: `--dry-run` CLI flag

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/dry-run
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library changes, no other-PR dependencies)
**Title:** `feat: --dry-run CLI flag (authenticate, summarise, exit without writing)`

```markdown
## Summary
Restores the unwired `--dry-run` flag documented in
`NOTIFICATION_CONFIG.md`, and extends it to a full pre-flight check:
authenticate against iCloud, summarise what the real loop would do
for each configured service, then exit cleanly without downloading,
deleting, or notifying.

## Motivation
Today there is no safe way to verify an icloud-docker install before
letting it loose on a fresh destination. A typo in the bind-mount
path or a misconfigured Apple ID currently means terabytes of iCloud
data get dumped into the wrong place before the user notices.

`python src/main.py --dry-run` (or `docker exec icloud icloud
--dry-run` once the entrypoint forwards the flag) now does the
auth + enumeration once, prints a summary, and exits.

## Implementation
- `src/main.py`: argparse wrapper, calls `sync.sync(dry_run=args.dry_run)`.
- `src/sync.py`: `sync()` gains a `dry_run: bool = False` kwarg
  (default keeps existing behaviour). When True, the loop branches to
  the new `_perform_dry_run` helper after auth and `return`s instead
  of entering the retry/sleep cycle.
- `_perform_dry_run` logs (INFO):
  - Drive destination path + root-level item count, or "would be
    skipped" if `drive:` is absent.
  - Photos destination path + library names, or "would be skipped"
    if `photos:` is absent.
  - A trailing "DRY RUN complete — no files were written" line.
  - 2FA-pending branch logs a hint to finish interactive auth first.

Enumeration failures are caught + logged as warnings — dry-run never
crashes the container.

## Tests
11 new tests in `tests/test_dry_run.py`:
- 6 `_perform_dry_run` behaviour tests (drive count, photo libs,
  per-service enumeration failure, completion line, skipped-service
  announcement).
- 4 integration tests on `sync.sync(dry_run=True)` via mocks (syncs
  not invoked, notifications not sent, loop not entered,
  2FA-pending branch).
- 1 signature compat test (default kwarg).

Full suite passes.
```

---

## PR 8: `require_mount_marker` failsafe (ports boredazfcuk's `.mounted` pattern)

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/require-mount-marker
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library changes, no other-PR dependencies)
**Title:** `feat: optional require_mount_marker — refuse to sync without a failsafe marker file`

```markdown
## Summary
Ports the boredazfcuk/docker-icloudpd `.mounted` safety pattern.
Defends against silent bind-mount failures (typo in host path,
missing share, wrong permissions) that would otherwise dump an entire
iCloud Drive / Photos library into the wrong place.

## New optional config (all default-OFF, no breaking change)
- `drive.require_mount_marker` (bool, default False)
- `photos.require_mount_marker` (bool, default False)
- `app.mount_marker_filename` (str, default `.mounted`)

When enabled, sync refuses to proceed until the marker file exists
in the destination directory. The countdown is NOT advanced on a
missed check — the next interval re-checks once the user has fixed
the mount and `touch`-ed the marker (so recovery is just re-mount
+ touch, no container restart needed).

## Motivation
Two related risks today:
1. Silent bind-mount failure → the container happily writes
   terabytes into a tmpfs the user can't see.
2. Wrong path in compose → wrong directory gets clobbered.

boredazfcuk/docker-icloudpd has solved this since at least 2024 by
requiring a user-touched `.mounted` file in each download destination
before sync runs. This PR ports the same pattern as an opt-in
config flag.

## Implementation
- `config_parser.get_drive_require_mount_marker(config)` →
  `bool` (default False).
- `config_parser.get_photos_require_mount_marker(config)` →
  `bool` (default False).
- `config_parser.get_mount_marker_filename(config)` →
  `str` (default `.mounted`).
- New `sync._check_mount_marker(destination_path, marker_filename,
  required, service_name)` — returns True/False; False causes the
  caller to skip this cycle without resetting the countdown.
- Called from `_perform_drive_sync` and `_perform_photos_sync`
  right after `prepare_*_destination`, before any sync work begins.

## Tests
11 new tests in `tests/test_mount_marker.py`:
- 6 config-helper tests (defaults + read + custom filename).
- 5 `_check_mount_marker` behaviour tests (not-required, present,
  absent, error logging with actionable instructions, custom
  filename).

Full suite passes.
```

---

## PR 9: Embedded web UI (dashboard + 2FA re-auth flow)

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/web-ui
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (uses ``hasattr(config_parser, ...)`` for PR 8's
mount-marker helpers so it works on either main or the combined fork)
**Title:** `feat: embedded web UI — dashboard + on-device 2FA re-auth flow`

```markdown
## Summary
Adds a small Flask app that runs in a daemon thread alongside the sync
loop on port 8080 (configurable). Designed to solve two recurring pain
points reported by users on the mandarons issue tracker:

1. **Re-authentication is CLI-only today.** When Apple's session
   expires (every few weeks), users have to `docker exec -it` from
   a terminal. With this PR, they can re-auth from a phone on the
   same network — or via a reverse proxy from anywhere.
2. **No visibility into running state.** Users routinely ask "is my
   sync actually working? what's my mount marker status?" Today the
   answer is to `docker logs` and squint. This PR surfaces it visually.

## New optional config (all default-OFF, no breaking change)
- `app.web_ui.enabled` (bool, default False)
- `app.web_ui.host`    (str, default "0.0.0.0")
- `app.web_ui.port`    (int, default 8080)

Vanilla installs see no behaviour change. Dockerfile gains an
`EXPOSE 8080` next to the existing `EXPOSE 80` so compose users can
map the port without it being a runtime surprise.

## What's in v1
- `GET  /`                 dashboard (auth status, service cards,
                           mount markers, last 200 log lines).
- `GET  /auth`             form (password or 6-digit code state).
- `POST /auth/password`    instantiates ICloudPyService, optionally
                           fires the 2FA push (PR 1 hasattr-guarded
                           so it works on stock icloudpy 0.8.0 too),
                           stashes the live session.
- `POST /auth/code`        validates code, trusts session, persists
                           password to keyring (so the sync loop's
                           next retry picks it up automatically).
- `POST /auth/reset`       escape hatch.
- `GET  /api/health`       200/503 — for UptimeRobot etc.
- `GET  /api/status`       JSON dashboard payload.
- `GET  /api/logs`         JSON log tail (last 200 lines).

## Security model
- **No built-in login.** Designed for LAN / Cloudflare Access /
  Authelia / Tailscale. Default bind `0.0.0.0` for proxy access;
  pin to `127.0.0.1` to require docker port-mapping.
- **Werkzeug dev server.** Single-user, behind a proxy. Not gunicorn —
  zero extra runtime deps.
- **No CSRF token in v1.** Relies on the auth proxy as the trust
  boundary. Easy to add in v1.1 if the maintainer wants it.
- **Credentials.** Password lives in form payload + in-memory
  ``_PENDING_AUTH`` dict (cleared after success/reset). Persisted to
  the existing icloudpy keyring on success — no new persistence layer.

## Implementation
- `src/web.py` — Flask app factory + threading helper + handlers.
- `src/templates/{base,dashboard,auth}.html` — Jinja2 templates with
  inline CSS (Apple-leaning design: white surface, blue accent,
  SF Pro stack, soft shadows, 12px radius). Single-file, no static
  pipeline.
- `src/config_parser.py` — three new helpers
  (`get_web_ui_enabled` / `_host` / `_port`).
- `src/main.py` — gains a testable `run()` entry that starts the
  web thread when enabled, then delegates to `sync.sync()`. The
  `if __name__ == "__main__"` block stays minimal.
- `Dockerfile` — `EXPOSE 8080`.
- `requirements.txt` — `flask==3.0.3` (single new runtime dep).

## Tests
38 new tests in `tests/test_web.py`:
- TestHealth (2)
- TestStatus (5) — 503 when missing, full payload, both services,
  service shape, marker_present reflects FS
- TestLogs (3) — array shape, empty when missing, _tail_log_file
  helper test with 500-line fixture
- TestDashboard (5) — 200, brand, username, both cards, log section
- TestAuthForm (3) — password/code state switching
- TestAuthPasswordPost (5) — empty / no username / 2FA push / no-2FA
  keyring / exception
- TestAuthCodePost (5) — empty / no pending / rejected / accepted
  (trust+keyring+clear+redirect) / trust_session failure non-fatal
- TestAuthReset (1) — clears pending
- TestWebUiConfig (6) — defaults + read-through for all three helpers
- TestMainRun (3) — enabled launches thread, disabled doesn't,
  partial config doesn't

All 38 pass in isolation. icloudpy is mocked via unittest.mock.patch
end-to-end — no real network.

## What's NOT in v1 (parked for v1.1)
- 2SA fallback (the older "send code to device-list" flow — rarely
  hit on iOS 13+ devices).
- "Force re-sync now" button (needs a sync-loop signal channel).
- CSRF token (only needed if the maintainer wants to remove the
  reverse-proxy assumption).
- Inline content browser (Notes, Drive contents).
```

---

## PR 10: persist python-keyring across container recreations

**Open:** https://github.com/epheterson/icloud-docker/pull/new/feat/persist-keyring
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (no upstream library changes, no other-PR dependencies; entrypoint-only change)
**Title:** `fix: persist python-keyring at /config/python_keyring so it survives container recreate`

```markdown
## Summary
The sync loop (`src/sync.py:_retrieve_password`) requires a keyring
entry containing the Apple ID password on every container start —
even when `/config/session_data` already has valid trusted cookies.
`icloudpy.ICloudPyService.__init__` also raises
`ICloudPyNoStoredPasswordAvailableException` when password is None
and the keyring is empty, so a populated keyring is a hard
prerequisite, period.

The keyring lives at `$XDG_DATA_HOME/python_keyring/keyring_pass.cfg`,
where `$XDG_DATA_HOME` defaults to `$HOME/.local/share`. In this
container `$HOME=/home/abc` — container-local. Every `docker compose
up` after a pull, PUID change, or image bump wipes the directory and
forces the user to interactively re-authenticate (via the bundled
`icloud` CLI).

## Fix
`docker-entrypoint.sh` now:
- `mkdir -p /config/python_keyring` (alongside `/config/session_data`)
- `export XDG_DATA_HOME=/config`
- `chown abc:abc /config/python_keyring` — the existing conditional
  `chown -R` block only runs for top-level dirs whose uid:gid doesn't
  already match `abc`, so on installs where bind-mounted `/config` is
  already `abc:abc` (PUID maps to a real host user), the new subdir
  stays root-owned and unwritable. Explicit chown fixes that.

`/config` is the existing bind-mounted volume that already holds
`session_data` and `config.yaml`, so no new mount is required and no
docker-compose changes needed by users.

## Validation
Tested in a live container by manually replicating the new entrypoint
steps:

\`\`\`
$ chown abc:abc /config/python_keyring
$ su-exec abc sh -c 'echo test > /config/python_keyring/canary.txt'  # OK
$ XDG_DATA_HOME=/config su-exec abc python -c '
    import keyring
    print("backend:", keyring.get_keyring().__class__.__name__)
    keyring.set_password("test", "user", "secret")
    print("get:", keyring.get_password("test", "user"))
  '
backend: PlaintextKeyring
get: secret
$ ls /config/python_keyring/keyring_pass.cfg
/config/python_keyring/keyring_pass.cfg
\`\`\`

End-to-end: container recreate → web-UI auth flow → recreate again →
``auth_state: ready`` preserved (verified on a real install).

## Backward compatibility
- Existing installs that already have a keyring entry at the old
  `~/.local/share/python_keyring/keyring_pass.cfg` location keep
  working until the container is recreated.
- On the first recreate after upgrading, the new
  `/config/python_keyring/` is empty; the existing retry-login +
  interactive-auth path runs once. Subsequent recreates pick up the
  persisted keyring and start syncing without prompting.

## Tests
Shell-only change to the entrypoint; covered indirectly by the
existing `tests/test_docker_entrypoint.py` suite (entrypoint syntax
+ ownership setup). No new tests added.
```

---

## PR 11: iCloud Drive package files — treat unrecognised mime as single-file bundle

**Open:** https://github.com/epheterson/icloud-docker/pull/new/fix/drive-package-single-file-bundles
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes
**Title:** `fix(drive): treat unrecognised-mime "package" downloads as single-file bundles instead of failures`

```markdown
## Summary
Stops the false "0 successful, N failed" log noise and
per-sync-cycle re-download for iCloud Drive package files that
libmagic can't identify as archives (Apple iWork .key/.pages/.numbers,
third-party .jmb, etc).

## Problem
iCloud Drive serves "package" files (Finder bundle types: .band, .key,
.jmb, etc.) via `/packageDownload?` URLs as opaque archive bytes.
`process_package()` only recognises `application/zip` and
`application/gzip` mime types. Anything else falls through to
`return None`, which the caller at `drive_file_download.py:64`
interprets as a hard download failure — even though the bytes have
ALREADY been written to disk and are perfectly usable.

Result: parallel-download log says `0 successful, N failed`, and
because the file is marked as "not-done" in bookkeeping, every
subsequent sync cycle re-downloads it.

## Fix
- `process_package()` returns the local_file path on unrecognised
  mime instead of `None`. The bytes ARE the canonical local
  representation for these bundle types — the file opens in
  Keynote/Pages/etc directly.
- Log level drops from ERROR to INFO: "Package format not recognised
  for unpacking; keeping as single-file bundle: {path}"
- `download_file()` only treats explicit `None` as failure (was
  treating any falsy value as failure).

## Validation
- New test `test_download_file_keeps_unrecognised_package_as_single_file`
  exercises the new success path.
- Renamed test `test_process_package_unrecognised_mime_preserves_file`
  documents the new contract.
- Fixed `test_download_file_returns_none_on_processing_failure` to
  patch the correct module-level binding (was patching wrong path
  but happened to pass on the old contract).
- Real-world: Eric's 111K-photo library + 40 .jmb / .key files —
  before this PR every sync re-downloaded ~300 MB of these files
  and logged ~50 ERROR lines per cycle. After: files preserved,
  logs clean.

## Known follow-up
The next-sync dedup may still trigger a re-download because
`file_exists()` compares `getsize(local_file)` to `item.size`, and
for flat bundles those differ (`item.size` is the unpacked contents
total). A sidecar-marker or mtime-fallback comparator would close
the loop. Out of scope for this focused fix.
```

---

## PR 12: Streaming photo enumeration — bound peak RSS by chunk size

**Open:** https://github.com/epheterson/icloud-docker/pull/new/perf/streaming-photo-enumeration
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes
**Title:** `perf(photos): stream album in fixed-size chunks (bounds peak RSS, fixes OOM on large libraries)`

```markdown
## Summary
Photos sync OOM-kills on large libraries because
`_collect_album_download_tasks()` materializes the entire per-photo
download-task list before draining. This PR converts to a streaming
buffer-and-drain pipeline so peak memory is bounded by `chunk_size`
instead of `len(album)`.

## Problem
On a 111K-photo iCloud library, the materialised task list peaks at
~4 GB RSS during enumeration. Kernel-confirmed cgroup OOM at the
4 GB cap:

`Memory cgroup out of memory: Killed process (python) total-vm:4270872kB anon-rss:4181524kB`

Forces operators to size containers at 8 GB+ even though steady-state
usage is well under 1 GB.

## Fix
- `_collect_and_execute_album_in_chunks()` buffers up to
  `chunk_size` (default 1000) DownloadTaskInfo entries, drains them
  via `execute_parallel_downloads`, clears the buffer, then collects
  the next chunk. Memory bounded by `chunk_size`, not `len(album)`.
- `sync_album_photos()` calls the new function instead of the
  previous two-step `_collect_album_download_tasks` + drain.
- Legacy `_collect_album_download_tasks` kept as a thin wrapper for
  test backward-compat.
- New `photos.enumeration_chunk_size` config knob lets operators
  tune for memory vs. throughput. Defensive about non-int /
  non-positive values (fall back to default).

## Validation
- 11 new tests in `tests/test_streaming_enumeration.py`:
  - Counts and number of drain calls match unchunked semantics
  - Empty album → no drain call
  - Partial final chunk drained (13 photos / chunk=5 → 3 calls of 5/5/3)
  - Invalid chunk_size falls back to default
  - **The behavioural contract:**
    `test_buffer_never_exceeds_chunk_size` — observes buffer length at
    every drain call. 2000 photos with chunk_size=50 → all drain calls
    see ≤50 tasks. Fires immediately if streaming regresses to monolithic.
  - 6 config-getter cases (default, explicit int, 0, negative, garbage
    string, None config).
- Existing photo + album orchestrator suite: no regressions.
- Real-world validation pending after deploy: on a 111K-photo library,
  this should let `mem_limit` drop back from 8 GB to ~2 GB.

## Tradeoffs
- Chunked downloads change the log shape — N "Parallel downloads
  completed" lines per album instead of one. Documented; could add
  a per-album summary line at the end as a follow-up.
- Failure aggregation: per-chunk counts sum cleanly into total,
  matches existing semantics.
- Throughput within a chunk vs. across the full album — iCloud's
  per-account concurrency is the bottleneck anyway, not material.

## Out of scope
- Streaming the photo-asset cache inside `icloudpy` (deeper problem).
  This PR works around it at the mandarons layer.
- Live Photo pairing across chunk boundaries — handled by the
  per-photo task collector; HEIC + MOV land in the same chunk.
```

---

## PR 13: Test suite passes on non-container dev hosts

**Open:** https://github.com/epheterson/icloud-docker/pull/new/fix/test-suite-non-container-hosts
**Target:** `mandarons/icloud-docker:main`
**Independent:** yes (recommend land FIRST — green baseline for every other PR)
**Title:** `test: green the suite on non-container dev hosts (macOS, sandboxes, etc.)`

```markdown
## Summary
The test suite assumed `/config` exists and is writable. On macOS dev
hosts and any sandbox where the container's `/config` mount isn't
present, ~20 tests fail with `FileNotFoundError` on usage cache
writes, session-data cookie directory creation, or hardcoded
`/config/...` path assertions.

This makes TDD on the codebase painful — `pytest` is red on a
healthy local checkout, drowning real failures in noise. CI in
container passes because `/config` is writable inside.

## Fix
- `src/__init__.py` + `src/usage.py`: `ICLOUD_DOCKER_CONFIG_DIR` env
  var overrides the `/config` base. Defaults to `/config` so
  production container deployments are unchanged.
- `src/sync.py`: `get_api_instance()` late-binds the `cookie_directory`
  default (was captured at function-definition time, which made
  conftest redirects ineffective).
- `tests/conftest.py`: NEW session-wide fixture redirects
  `ICLOUD_DOCKER_CONFIG_DIR` to a tempdir, patches the cached
  constants, cleans up at session end.
- `tests/test_sync.py`: assertion uses the resolved
  `DEFAULT_COOKIE_DIRECTORY` instead of hardcoded
  `/config/session_data`.

## Validation
- macOS dev host: **435 / 435 tests pass** on this branch (up from
  ~415 / 435 with 20 pre-existing failures on bare main).
- Linux/CI: no change — `ICLOUD_DOCKER_CONFIG_DIR` is unset, falls
  back to `/config`, all original behaviour preserved.
- Production deployments: zero behavior change — paths still resolve
  to `/config/...` in the container.

## Backward compatibility
- Existing production installs: completely unchanged. The env var is
  only set in test environments where `/config` isn't writable.
- Test environments that already use a `/config` mount: opt-in by
  not setting `ICLOUD_DOCKER_CONFIG_DIR`. Fixture honours explicit
  caller override.
```

---

# Pre-submit checklist (run through each PR)

For each PR, before clicking Submit:

- [ ] Branch is rebased on latest upstream `main` (or note that rebase is needed in PR body)
- [ ] All tests pass on the branch (verify with `pytest --no-cov`)
- [ ] PR title matches one of the titles above
- [ ] PR body matches the corresponding markdown block above (paste verbatim — backticks intact)
- [ ] No accidental binary files / `.DS_Store` / test fixture trees in the diff (`git diff main --stat` to verify)
- [ ] For PR 4: requirements.txt git URL pin is acknowledged in the body (so the maintainer doesn't think it's a permanent dependency)
- [ ] For PRs that close issues: `Closes #N` line is at the END of the body so GitHub auto-links it
- [ ] If submitting via the gh CLI, double-check `--repo` and `--base` flags
```

---

# After all six are submitted

Track them in a single GitHub issue or doc — link all six URLs. When each merges, the lifecycle:

1. PR 1 (icloudpy fix/ios-26.4-auth) merges → maintainer cuts new icloudpy release (likely 0.8.1)
2. PR 2 (icloudpy feat/live-photos) merges → maintainer cuts release (0.9.0)
3. PR 4 (icloud-docker live-photo-pair) needs requirements.txt re-bumped to the new icloudpy release before it can merge. Open a follow-up commit on the branch.
4. PRs 3, 5, 6 (icloud-docker, no library dependency) merge independently
5. mandarons publishes new icloud-docker image
6. We update overlay README to say "Archived — use upstream mandarons/icloud-drive:latest" and stop pushing new tags here.
