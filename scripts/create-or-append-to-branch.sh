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
  GIT_INDEX_FILE="$TEMP_INDEX" git read-tree "$PARENT"
else
  GIT_INDEX_FILE="$TEMP_INDEX" git read-tree --empty
fi

for path in "$@"; do
  if [ -e "$path" ]; then
    GIT_INDEX_FILE="$TEMP_INDEX" git add -f "$path"
  else
    echo "  warn: $path not found, skipping" >&2
  fi
done

GIT_INDEX_FILE="$TEMP_INDEX" git diff-index --cached --quiet "$origin_ref" 2>/dev/null \
  && { echo "  No changes to $BRANCH" >&2; exit 0; }

TREE=$(GIT_INDEX_FILE="$TEMP_INDEX" git write-tree)

if [ -n "$PARENT" ]; then
  COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -p "$PARENT" -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$TREE")
  echo "  Pushing commit ${COMMIT:0:7} (parent: ${PARENT:0:7})..." >&2
  if ! git push origin "$COMMIT:refs/heads/$BRANCH" 2>&1; then
    remote_sha=$(git ls-remote origin "$BRANCH" | awk '{print $1}')
    echo "  Error: push rejected — local: ${COMMIT:0:7}, remote: ${remote_sha:0:7}" >&2
    echo "  Fix: re-run the workflow" >&2
    exit 1
  fi
else
  COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$TREE")
  git push origin "$COMMIT:refs/heads/$BRANCH"
fi
echo "  Pushed to $BRANCH (commit ${COMMIT:0:7})" >&2
