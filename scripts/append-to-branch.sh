#!/usr/bin/env bash
set -euo pipefail

BRANCH="$1"
shift

TEMP_INDEX=".git/cache-index-$$"
cleanup() { rm -f "$TEMP_INDEX"; }
trap cleanup EXIT

echo "Storing to branch $BRANCH..." >&2

git fetch origin "$BRANCH" 2>/dev/null || true

origin_ref="origin/$BRANCH"

if ! git rev-parse --verify "$origin_ref" >/dev/null 2>&1; then
  echo "  Error: branch $BRANCH does not exist" >&2
  exit 1
fi

PARENT=$(git rev-parse "$origin_ref")
echo "  Base: ${PARENT:0:7}" >&2

# Build content tree (parent tree + new cache files, overlay only)
GIT_INDEX_FILE="$TEMP_INDEX" git read-tree --empty
GIT_INDEX_FILE="$TEMP_INDEX" git read-tree "$PARENT"

for path in "$@"; do
  if [ -e "$path" ]; then
    GIT_INDEX_FILE="$TEMP_INDEX" git add -f "$path"
    echo "  Added $path" >&2
  else
    echo "  warn: $path not found, skipping" >&2
  fi
done

GIT_INDEX_FILE="$TEMP_INDEX" git diff-index --cached --quiet "$origin_ref" 2>/dev/null \
  && { echo "  No changes to $BRANCH" >&2; exit 0; }

CONTENT_TREE=$(GIT_INDEX_FILE="$TEMP_INDEX" git write-tree)
echo "  Content tree: ${CONTENT_TREE:0:7}" >&2

CONTENT_COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
  commit-tree -p "$PARENT" -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$CONTENT_TREE")
echo "  Content commit: ${CONTENT_COMMIT:0:7}" >&2

git push origin "$CONTENT_COMMIT:refs/heads/$BRANCH" 2>&1 || {
  remote_sha=$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)
  remote_msg=$(git log --format=%s -1 "$remote_sha" 2>/dev/null || echo "n/a")
  echo "  Error: push rejected — branch updated since fetch" >&2
  echo "  Local:  ${CONTENT_COMMIT:0:7}" >&2
  echo "  Base:   ${PARENT:0:7}" >&2
  echo "  Remote: ${remote_sha:0:7} — $remote_msg" >&2
  echo "  Fix: re-run the workflow" >&2
  exit 1
}

echo "  Pushed to $BRANCH (${PARENT:0:7} → ${CONTENT_COMMIT:0:7})" >&2
