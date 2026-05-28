# Upstream PR submission guide (eight PRs, push tonight)

Eight PRs total — two to `mandarons/icloudpy`, six to `mandarons/icloud-docker`. Each is a single feature for clean maintainer review. Submit in the order below — independence note for each.

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
