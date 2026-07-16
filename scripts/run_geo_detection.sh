#!/bin/bash
# Run geo division detection after sync
# Called from sync.yml
set -e

LIMIT="${1:-200}"  # 默认每批条数上限
BATCH="${2:-20}"
STRATEGY="${3:-proportional}"
TIME_BUDGET="${4:-300}"

ARGS="--batch $BATCH --strategy $STRATEGY --time $TIME_BUDGET"
[ -n "$LIMIT" ] && ARGS="$ARGS --limit $LIMIT"

echo "Starting geo region detection..."
echo "Args: $ARGS"

bundle exec exe/workouts geo detect $ARGS

echo "Geo detection complete."
