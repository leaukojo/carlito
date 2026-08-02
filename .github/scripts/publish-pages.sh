#!/usr/bin/env bash
#
# Republishes the gh-pages branch as a single orphan commit.
#
#   publish-pages.sh dev <build-dir>   replace gh-pages:/dev/ with <build-dir>
#   publish-pages.sh promote           copy gh-pages:/dev/ over gh-pages:/stable/
#
# gh-pages is ALWAYS rewritten as one orphan commit and force-pushed: a web build
# is ~50 MB of .wasm/.pck, and keeping history would accumulate every superseded
# copy of it forever. There is nothing worth keeping in that history - the source
# history lives on dev/main, and every published build is reproducible from it.
#
# Promotion copies bytes, never rebuilds, so the artifact approved on dev is
# byte-identical to the one that becomes stable.
#
# Both callers hold the same `concurrency: gh-pages` group, because two
# force-pushes racing here would silently drop one channel's update.
#
# Requires GITHUB_TOKEN, GITHUB_REPOSITORY, and SITE_SHA (the commit the published
# bytes were built from) in the environment. SITE_SHA is passed explicitly rather
# than read from GITHUB_SHA: on a workflow_dispatch that is the ref the run was
# dispatched from, which is not necessarily the tip of dev being promoted.
set -euo pipefail

MODE="${1:-}"
: "${SITE_SHA:?SITE_SHA must name the commit these bytes were built from}"

# Validate arguments before cloning ~50 MB of gh-pages.
case "$MODE" in
  dev)
    SRC="$(cd "${2:?usage: publish-pages.sh dev <build-dir>}" && pwd)"
    [ -f "$SRC/index.html" ] || { echo "no index.html in $SRC - the export step did not produce a site"; exit 1; }
    ;;
  promote) ;;
  *) echo "usage: publish-pages.sh dev <build-dir> | promote"; exit 1 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel)"
REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
WORK="$(mktemp -d)"
GHP="$WORK/ghp"

# Shallow clone of the branch as it stands, so the channel we are NOT touching
# survives the rewrite. On the very first publish the branch does not exist yet.
if [ -n "$(git ls-remote --heads "$REMOTE" gh-pages)" ]; then
  git clone --quiet --depth 1 --branch gh-pages "$REMOTE" "$GHP"
else
  echo "gh-pages does not exist yet - starting from an empty tree"
  mkdir -p "$GHP"
  git -C "$GHP" init --quiet
  git -C "$GHP" remote add origin "$REMOTE"
fi

if [ "$MODE" = dev ]; then
  # Replace, never merge: a stale c2-<oldsha>.* left behind would be served forever.
  rm -rf "$GHP/dev"
  mkdir -p "$GHP/dev"
  cp -r "$SRC/." "$GHP/dev/"
  MSG="deploy dev @ ${SITE_SHA}"
else
  [ -f "$GHP/dev/index.html" ] || { echo "gh-pages:/dev/ is empty - push to dev and let CI publish before promoting"; exit 1; }
  rm -rf "$GHP/stable"
  mkdir -p "$GHP/stable"
  cp -r "$GHP/dev/." "$GHP/stable/"
  MSG="promote dev -> stable @ ${SITE_SHA}"
fi

# Root redirect + .nojekyll come from the repo every time, so gh-pages never
# becomes the source of truth for them.
cp -r "$REPO_ROOT/.github/pages-root/." "$GHP/"

cd "$GHP"
git checkout --quiet --orphan deploy
git add -A
git -c user.name='carlito-ci' -c user.email='carlito-ci@users.noreply.github.com' \
    commit --quiet -m "$MSG"
git push --force --quiet origin deploy:gh-pages
echo "published: $MSG"
