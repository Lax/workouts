#!/usr/bin/env bash
set -euo pipefail

BRANCH="$1"
CACHE_PATHS="$2"

TEMP_INDEX=".git/cache-index-$$"
cleanup() { rm -f "$TEMP_INDEX"; }
trap cleanup EXIT

echo "Saving to branch $BRANCH..." >&2

git fetch origin "$BRANCH" 2>/dev/null || true

GIT_INDEX_FILE="$TEMP_INDEX" git read-tree --empty

for path in $CACHE_PATHS; do
  [ -e "$path" ] && GIT_INDEX_FILE="$TEMP_INDEX" git add -f "$path"
done

GIT_INDEX_FILE="$TEMP_INDEX" git diff-index --cached --quiet "origin/$BRANCH" 2>/dev/null && {
  echo "No changes to $BRANCH" >&2
  exit 0
}

TREE=$(GIT_INDEX_FILE="$TEMP_INDEX" git write-tree)

if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  PARENT=$(git rev-parse "origin/$BRANCH")
  COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -p "$PARENT" -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$TREE")
else
  COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
    commit-tree -m "store($BRANCH): $(date -u +%Y%m%d-%H%M%S)" "$TREE")
fi

git push origin "$COMMIT:refs/heads/$BRANCH"
echo "Pushed to $BRANCH (commit $COMMIT)" >&2
