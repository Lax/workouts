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
PARENT=""

if git rev-parse --verify "$origin_ref" >/dev/null 2>&1; then
  PARENT=$(git rev-parse "$origin_ref")
  echo "  Base: ${PARENT:0:7}" >&2
else
  echo "  New branch (no parent)" >&2
fi

# ── Step 1: Build content tree (parent files + new cache files) ──
GIT_INDEX_FILE="$TEMP_INDEX" git read-tree --empty
[ -n "$PARENT" ] && GIT_INDEX_FILE="$TEMP_INDEX" git read-tree "$PARENT"

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

# ── Step 2: Push empty commit (clears prior state) ──
GIT_INDEX_FILE="$TEMP_INDEX" git read-tree --empty
EMPTY_TREE=$(GIT_INDEX_FILE="$TEMP_INDEX" git write-tree)

if [ -n "$PARENT" ]; then
  EMPTY_COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -p "$PARENT" -m "clear($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$EMPTY_TREE")
  echo "  Empty commit: ${EMPTY_COMMIT:0:7} (parent: ${PARENT:0:7})" >&2
else
  EMPTY_COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -m "init($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$EMPTY_TREE")
  echo "  Init commit: ${EMPTY_COMMIT:0:7}" >&2
fi

git push origin "$EMPTY_COMMIT:refs/heads/$BRANCH" 2>&1 || {
  remote_sha=$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)
  remote_msg=$(git log --format=%s -1 "$remote_sha" 2>/dev/null || echo "n/a")
  echo "  Error: push rejected — branch updated since fetch" >&2
  echo "  Local (empty): ${EMPTY_COMMIT:0:7}" >&2
  [ -n "$PARENT" ] && echo "    Parent:       ${PARENT:0:7}" >&2
  echo "  Remote tip:    ${remote_sha:0:7} — $remote_msg" >&2
  echo "  Fix: re-run the workflow" >&2
  exit 1
}

# ── Step 3: Push content commit (parent = empty commit) ──
CONTENT_COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
  commit-tree -p "$EMPTY_COMMIT" -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$CONTENT_TREE")
echo "  Content commit: ${CONTENT_COMMIT:0:7}" >&2

git push origin "$CONTENT_COMMIT:refs/heads/$BRANCH" 2>&1 || {
  remote_sha=$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)
  remote_msg=$(git log --format=%s -1 "$remote_sha" 2>/dev/null || echo "n/a")
  echo "  Error: push rejected — branch updated since empty push" >&2
  echo "  Empty:         ${EMPTY_COMMIT:0:7}" >&2
  echo "  Content:       ${CONTENT_COMMIT:0:7}" >&2
  echo "  Remote tip:    ${remote_sha:0:7} — $remote_msg" >&2
  echo "  Fix: re-run the workflow" >&2
  exit 1
}

echo "  Pushed to $BRANCH (${EMPTY_COMMIT:0:7} → ${CONTENT_COMMIT:0:7})" >&2
