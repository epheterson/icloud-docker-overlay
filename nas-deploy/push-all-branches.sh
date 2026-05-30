#!/usr/bin/env bash
#
# push-all-branches.sh — push every icloud-docker branch to
# epheterson/icloud-docker so PRs can be opened against
# mandarons/icloud-docker.
#
# Safe defaults:
#   - --force-with-lease (not --force): refuses to overwrite if the
#     remote moved since our last fetch, preventing data-loss in the
#     unlikely event someone else pushed to your fork in the meantime.
#   - exits on first error (set -e) so a failed push doesn't get
#     hidden under successful ones.
#   - dry-runs first, only pushes after a one-key confirm.
#
# After this runs successfully, Claude will:
#   - post the two discussion drafts in mandarons/icloudpy and
#     mandarons/icloud-docker via gh CLI
#   - open the 13 PRs in the dependency order from UPSTREAM-PRS.md

set -euo pipefail

cd ~/Repos/icloud-docker

# Verify we're in the right repo + on a clean tree before pushing anything.
test -f Dockerfile || { echo "ERROR: not in icloud-docker repo"; exit 1; }
git diff --quiet && git diff --cached --quiet || {
  echo "ERROR: working tree dirty — commit or stash before pushing"
  git status --short
  exit 1
}

git fetch origin --quiet

# Branches grouped by push semantics.
FORCE_PUSH=(
  feat/dry-run                              # rebuilt clean (was contaminated by require-mount-marker merge)
  feat/web-ui                               # 4 polish commits (running state, mobile, polling, header)
  feat/persist-keyring                      # chown + XDG_DATA_HOME redesign
  feat/photos-live-photo-pair-download      # tonight's tweaks
  feat/photos-preserve-originals-as-bak     # tonight's tweaks
)

NEW_PUSH=(
  fix/test-suite-non-container-hosts        # PR 13 — green CI baseline
  fix/drive-package-single-file-bundles     # PR 11 — Drive package handling
  perf/streaming-photo-enumeration          # PR 12 — bounded photo RSS
)

NORMAL_PUSH=(
  combined/all-features                     # the actual build branch, 14+ commits ahead
)

# Print plan first (dry-runs that don't actually push).
echo "================================================================"
echo "PLAN (no pushes yet, just dry-runs):"
echo "================================================================"
echo
echo "[force-with-lease — history rewritten today]"
for b in "${FORCE_PUSH[@]}"; do
  printf "  %-50s  " "$b"
  if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
    git log --oneline "origin/$b..$b" 2>/dev/null | head -1 || echo "(no new commits — skip)"
  else
    echo "(no origin ref — will become first-push)"
  fi
done
echo
echo "[first push — new branches]"
for b in "${NEW_PUSH[@]}"; do
  printf "  %-50s  " "$b"
  git log --oneline "$b" 2>/dev/null | head -1
done
echo
echo "[regular push]"
for b in "${NORMAL_PUSH[@]}"; do
  printf "  %-50s  +%s commits\n" "$b" "$(git rev-list --count "origin/$b..$b" 2>/dev/null)"
done
echo
echo "================================================================"
read -rp "Press enter to execute these pushes, or Ctrl-C to abort: "
echo

# Execute.
for b in "${FORCE_PUSH[@]}"; do
  echo "→ git push --force-with-lease origin $b"
  git push --force-with-lease origin "$b"
  echo
done

for b in "${NEW_PUSH[@]}"; do
  echo "→ git push -u origin $b"
  git push -u origin "$b"
  echo
done

for b in "${NORMAL_PUSH[@]}"; do
  echo "→ git push origin $b"
  git push origin "$b"
  echo
done

echo "================================================================"
echo "All branches pushed. Verify on GitHub:"
echo "  https://github.com/epheterson/icloud-docker/branches"
echo
echo "Next step (Claude will handle):"
echo "  1. Post discussion drafts in mandarons/icloudpy + mandarons/icloud-docker"
echo "  2. Open the 13 PRs in the order from UPSTREAM-PRS.md"
echo "================================================================"
