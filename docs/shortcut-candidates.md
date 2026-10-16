# Phone shortcut candidates

Source: a read-only Haiku scan of `~/.claude/projects` and `~/.claude/history.jsonl` on 2026-10-15. Counts are approximate.

## What the transcripts show

Every project lives under `~/Projects`. Nothing runs from `~/Downloads`, so the folder picker should default to `~/Projects`. The busiest projects are ezhomesteading (346 sessions), personal-config (128), buy-in (92), emoney (58), usdeed (56) and felto (47).

The most common replies inside a session are "continue" (61 exact), "yes" (33), "remove comments" (14) and "commit this" (13). Common session openers are "delegate next item in passoff", "whats next" and "complete the next opus task". Inside Claude, `/model`, `/clear` and `/usage` are the most used slash commands.

Dev servers almost never appear as Bash calls. The common checks are `bun run typecheck`, `bun run lint`, `bun test` and `git status --short`.

## Candidates

| Label | Command or text | Kind |
|---|---|---|
| Claude in ezhomesteading | `tmux new -A -s ezh -c ~/Projects/ezhomesteading claude` | new or attach |
| Claude in personal-config | `tmux new -A -s pc -c ~/Projects/personal-config claude` | new or attach |
| Claude in buy-in | `tmux new -A -s buyin -c ~/Projects/buy-in claude` | new or attach |
| Session list | `tmux ls` | shell |
| Continue | `continue` + Return | text into live session |
| Yes | `yes` + Return | text into live session |
| Commit this | `commit this` + Return | text into live session |
| What's next | `whats next` + Return | text into live session |
| Delegate next | `delegate next item in passoff` + Return | text into live session |
| Usage | `/usage` + Return | text into live session |
| Verify (ezh) | `bun run typecheck && bun run lint && bun test` in a new tmux window | shell |
| Git glance | `git status --short && git worktree list` | shell |

Two kinds of shortcut follow from this. Shell snippets run before or outside Claude. Reply chips type short text into a running Claude session, and they are the bigger win on a phone because "continue", "yes" and "commit this" make up most mid-session input.

The app ships the reply chips Continue, Yes, Commit this, What's next, Delegate next and /usage as defaults. These apply only to a phone that has no saved snippets. The new-or-attach rows are covered by New Claude session in the Sessions tab, and the shell rows are left for the user to add in Settings > Snippets.
