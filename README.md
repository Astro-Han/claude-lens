# Claude Pace

A lightweight Claude Code status line and rate limit tracker that shows your 5-hour and 7-day quota usage in real time. Pure Bash + jq, single file, zero npm.

If you are searching for a Claude Code statusline, a Claude Code quota monitor, or a Claude Code usage tracker, claude-pace is built for that narrow job. It shows not only how much quota you have used, but whether your current burn rate is sustainable before the window resets.

![claude-pace statusline demo](.github/claude-pace-demo.gif)

## TL;DR

- Claude Code status line with `5h` and `7d` quota usage, reset countdowns, and pace delta
- Pace-aware rate limit tracking, `⇡15%` means overspending, `⇣15%` means headroom
- Pure Bash + jq, single file, no Node.js runtime and no lockfile churn
- Install as a Claude Code plugin, with `npx`, or as a single script

Most statuslines show "you used 60%." That number means nothing without context. 60% with 30 minutes left? Fine, the window resets soon. 60% with 4 hours left? You are about to hit the wall. claude-pace compares your burn rate to the time remaining and shows the delta.

- **⇣15%** green = you've used 15% less than expected. Headroom. Keep going.
- **⇡15%** red = you're burning 15% faster than sustainable. Slow down.
- **15%** / **20%** = used in the 5h and 7d windows. **3h** = resets in 3 hours.
- Top line: model, effort, project `(branch)`, `3f +24 -7` = git diff stats

Claude Code supports custom status lines through its `statusLine` setting and `/statusline` workflow in the official docs:

- [Customize your status line](https://code.claude.com/docs/en/statusline)
- [Claude Code settings](https://docs.anthropic.com/en/docs/claude-code/settings)

## Table of Contents

- [Install This Claude Code Statusline](#install-this-claude-code-statusline)
- [Upgrade](#upgrade)
- [Claude Code Statusline Comparison](#claude-code-statusline-comparison)
- [How Claude Pace Tracks Quota](#how-claude-pace-tracks-quota)
- [Claude Code Statusline FAQ](#claude-code-statusline-faq)

## Install This Claude Code Statusline

Requires `jq`.

**Plugin (recommended):**

Inside Claude Code:

```
/plugin marketplace add Astro-Han/claude-pace
/plugin install claude-pace
/reload-plugins
/claude-pace:setup
```

**npx:**

```bash
npx claude-pace
```

Restart Claude Code. Done.

**Manual:**

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-pace/main/claude-pace.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Restart Claude Code. Done.

To remove: delete the `statusLine` block from `~/.claude/settings.json`.

## Upgrade

- **Plugin:** `/claude-pace:setup` (pulls the latest from GitHub)
- **npx:** `npx claude-pace@latest`
- **Manual:** Re-run the `curl` command above.

Release notifications: Watch this repo → Custom → Releases.

## Claude Code Statusline Comparison

|  | claude-pace | [claude-hud](https://github.com/jarrodwatts/claude-hud) | [CCometixLine](https://github.com/Haleclipse/CCometixLine) | [ccstatusline](https://github.com/sirmalloc/ccstatusline) |
|---|---|---|---|---|
| Runtime | `jq` | Node.js 18+ / npm | Compiled (Rust) | Node.js / npm |
| Codebase | Single Bash file | 1000+ lines + node_modules | Compiled binary | 1000+ lines + node_modules |
| Rate limit tracking | 5h + 7d usage %, pace delta, reset countdown | Usage % | Usage % (planned) | None (formatting only) |
| Execution | ~10ms | ~90ms | ~5ms | ~90ms |
| Memory | ~2 MB | ~57 MB | ~3 MB | ~57 MB |

Execution and memory measured on Apple Silicon, 300 runs, same stdin JSON.

Need themes, powerline aesthetics, or TUI config? Try [ccstatusline](https://github.com/sirmalloc/ccstatusline). The entire source of claude-pace is [one file](claude-pace.sh). Read it.

## How Claude Pace Tracks Quota

Claude Code polls the statusline every ~300ms:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits`; fallback to last-known private cache when `rate_limits` is absent | Private cache root, accepted only before cached reset |
| Git branch + diff | `git` commands | Private cache dir, 5s TTL |

Best experience is on Claude Code `2.1.80+`, where `rate_limits` is available in statusline stdin. When a later statusline run omits `rate_limits`, claude-pace can reuse the last known stdin quota snapshot from its private cache until either cached reset time expires.

Cache files live in a private per-user directory (`$XDG_RUNTIME_DIR/claude-pace` or `~/.cache/claude-pace`, mode 700). All cache reads are validated before use. No files are ever written to shared `/tmp`.

## Claude Code Statusline FAQ

**Does it need Node.js?**
No. Only `jq` (available via `brew install jq` or your package manager). No npm, no node_modules, no lock files.

**How does pace tracking work?**
claude-pace compares your current usage percentage to the fraction of time elapsed in each window (5-hour and 7-day). If you've used 40% of your quota but only 30% of the time has passed, the pace delta shows ⇡10% (red, burning too fast). If you've used 30% with 40% of time elapsed, it shows ⇣10% (green, headroom).

**Does it make network calls?**
No. Quota data comes from stdin `rate_limits` on Claude Code `2.1.80+`. If a later statusline run omits `rate_limits`, claude-pace can reuse the last known stdin quota snapshot from its private cache as long as that snapshot's reset times are still in the future. Otherwise it falls back to `--` and may still show the local session cost.

**Can I inspect the source?**
The entire tool is [one Bash file](claude-pace.sh). Read it before you install it.

## Also by the Author

[**diffpane**](https://github.com/Astro-Han/diffpane) - Real-time TUI diff viewer for AI coding agents. See what Claude Code changes as it happens.

## License

MIT

*Last updated: 2026-04-13 · v0.8.2*
