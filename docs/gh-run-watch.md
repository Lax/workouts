# gh-run-watch — Smart CI Wait

Predicts CI duration from historical data, waits efficiently, then shows real-time logs.

## Install

```bash
cp scripts/gh-run-watch ~/.local/share/gh/extensions/gh-run-watch/
chmod +x ~/.local/share/gh/extensions/gh-run-watch/gh-run-watch
```

Verify:

```bash
gh run-watch --help
```

## Usage

| Command | Behavior |
|---|---|
| `gh run-watch` | Watch latest run on current branch |
| `gh run-watch 12345678` | Watch specific run |
| `gh run-watch --compact` | Show only relevant/failed steps |
| `gh run-watch --exit-status` | Exit non-zero on failure |
| `gh run-watch -q` | Suppress progress output |
| `git push && gh run-watch -q --compact --exit-status` | Full CI gate (最常用) |

All flags pass through to `gh run watch`. See `gh run watch --help` for the full list.

## Algorithm

```
1.  Get latest run_id from current branch
2.  Predict duration: median of last 50 successful runs
3.  Initial sleep: predicted + 15s
4.  Delegate to gh run watch (3s interval + exponential backoff)
5.  Exit with gh run watch's exit code
```

### Prediction

- Source: Last 50 success runs of `ci.yml` on `main`
- Statistic: **Median** (vs mean — resistant to outliers)
- Floor: 10s (avoid 0 prediction for new repos)
- Debug: `DEBUG_CI_WAIT=1 gh run-watch` prints timing

## Why not raw `gh run watch`

| | `gh run watch` | `gh run-watch` |
|---|---|---|
| Initial delay | None — starts polling immediately | Predicted + 15s — skips empty polling |
| Log noise | All steps by default | `--compact` shows only failures |
| CI scripting | Manual `run-id` lookup | Auto-resolves latest run |
| Exit code | `--exit-status` flag | Same (passed through) |

Example of time saved (based on 72s median):

```
gh run watch:   72s of empty polling  ★
gh run-watch:   87s sleep → run finishes immediately after  ★★★
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `no recent run found` | No CI triggered on branch | Push first, or use `gh run-watch <run-id>` |
| Timeout after 10min | Runner queue delay | Check `gh run view <run-id>` for status |
| Prediction way off | Few historical runs (< 5) | Falls back to min 10s; runs adjust quickly |
