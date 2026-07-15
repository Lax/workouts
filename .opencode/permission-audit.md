# Permission Audit — 2026-07-15 theme-simple session

Lessons from a session where subagent permission gaps caused excess prompts (rg, tail, sed, rm) and
a preventable force-push. Reference for future practice.

## Key findings

**Excess prompts root cause**: agent `.opencode/agents/frontend-dev.md` had `bash: "*": "ask"`.
This overrode global `~/.config/opencode/opencode.jsonc` `bash: "*": "allow"`. Every bash command not
explicitly listed — including `rg`, `tail`, `sed`, `rm` — triggered a permission dialog.

Fixed in commit `c00c715`: `"*": "ask"` → `"*": "allow"`. Global config already blocks the genuinely
dangerous patterns (`git config --global`, `gh auth`). Agent-level `*: ask` was redundant.

**Force-push root cause**: `git commit --amend` after push, then `git push --force-with-lease`.
Two amends in one session, each rewriting an already-pushed commit.

Rule: once pushed, no amend. If a fix is needed after push, make a new commit.

## Recommendations

| Concern | Rule |
|---|---|
| Agent bash permission | `"*": "allow"` unless there is a specific command to deny. Global config handles the dangerous ones. |
| Amend after push | Never. New commit only. |
| Force push | Only when explicitly approved by user. Print WARNING + rationale before executing. |
| Home dir writes | Agent should escalate to main session. Main session executes the `cp`/`write` to `~/.config` or `~/.local`. |
| File deletion | Accept the built-in safety prompt. Infrequent enough (2× per session) that it is not worth a workaround. |
