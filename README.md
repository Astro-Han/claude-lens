# Claude Pace

A lightweight status line for Claude Code that tracks your 5-hour and 7-day rate limit usage in real time. Pure Bash + jq, single file, zero npm.

Most statuslines show "you used 60%." That number means nothing without context. 60% with 30 minutes left? Fine, the window resets soon. 60% with 4 hours left? You're about to hit the wall. claude-pace compares your burn rate to the time remaining and shows the delta: are you ahead of pace or behind?

![claude-pace statusline demo](.github/claude-pace-demo.gif)

- **⇣15%** green = you've used 15% less than expected. Headroom. Keep going.
- **⇡15%** red = you're burning 15% faster than sustainable. Slow down.
- **15%** / **20%** = used in the 5h and 7d windows. **3h** = resets in 3 hours.
- Top line: model, effort, project `(branch)`, `3f +24 -7` = git diff stats

## Install

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

## How It Compares

|  | claude-pace | [claude-hud](https://github.com/jarrodwatts/claude-hud) | [CCometixLine](https://github.com/Haleclipse/CCometixLine) | [ccstatusline](https://github.com/sirmalloc/ccstatusline) |
|---|---|---|---|---|
| Runtime | `jq` | Node.js 18+ / npm | Compiled (Rust) | Node.js / npm |
| Codebase | Single Bash file | 1000+ lines + node_modules | Compiled binary | 1000+ lines + node_modules |
| Rate limit tracking | 5h + 7d usage %, pace delta, reset countdown | Usage % | Usage % (planned) | None (formatting only) |
| Execution | ~10ms | ~90ms | ~5ms | ~90ms |
| Memory | ~2 MB | ~57 MB | ~3 MB | ~57 MB |

Execution and memory measured on Apple Silicon, 300 runs, same stdin JSON.

Need themes, powerline aesthetics, or TUI config? Try [ccstatusline](https://github.com/sirmalloc/ccstatusline). The entire source of claude-pace is [one file](claude-pace.sh). Read it.

## Under the Hood

Claude Code polls the statusline every ~300ms:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits` (CC >= 2.1.80) | None needed (real-time) |
| Quota fallback | Anthropic Usage API (CC < 2.1.80) | Private cache dir, 300s TTL, async background refresh |
| Git branch + diff | `git` commands | Private cache dir, 5s TTL |

On Claude Code >= 2.1.80, usage data comes directly from stdin. No network calls. On older versions, it falls back to the Usage API in a background subshell so the statusline never blocks.

Cache files live in a private per-user directory (`$XDG_RUNTIME_DIR/claude-pace` or `~/.cache/claude-pace`, mode 700). All cache reads are validated before use. No files are ever written to shared `/tmp`.

## FAQ

**Does it need Node.js?**
No. Only `jq` (available via `brew install jq` or your package manager). No npm, no node_modules, no lock files.

**How does pace tracking work?**
claude-pace compares your current usage percentage to the fraction of time elapsed in each window (5-hour and 7-day). If you've used 40% of your quota but only 30% of the time has passed, the pace delta shows ⇡10% (red, burning too fast). If you've used 30% with 40% of time elapsed, it shows ⇣10% (green, headroom).

**Does it make network calls?**
On Claude Code >= 2.1.80, no. All data comes from stdin. On older versions, it falls back to the Anthropic Usage API in a background subshell (opt-out via `CLAUDE_PACE_API_FALLBACK=0`).

**Can I inspect the source?**
The entire tool is [one Bash file](claude-pace.sh). Read it before you install it.

## Also by the Author

[**diffpane**](https://github.com/Astro-Han/diffpane) - Real-time TUI diff viewer for AI coding agents. See what Claude Code changes as it happens.

## License

MIT

*Last updated: 2026-04-05 · v0.7.3*
