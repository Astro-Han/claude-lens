# Claude Lens

A lightweight statusline for Claude Code. ~165 lines of Bash + jq.

Other statuslines show how much you *used*. Claude Lens shows whether your *pace* is sustainable -- so you know to keep pushing or ease off before hitting a wall.

![claude-lens statusline](.github/claude-lens-showcase.png)

Reading the screenshot:

- **92%** remaining in the 5h window, **29%** remaining in the 7d window
- **+17%** green = you've used 17% less than expected at this point. Headroom. Keep going.
- **(3h)** = this window resets in 3 hours
- Colors: green (>30% left), yellow (11-30%), red (<=10%)

The top line shows model, effort, context size, project directory, and git branch with diff stats.

## Install

Requires `jq`.

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh
chmod +x ~/.claude/statusline.sh

claude config set statusLine.command ~/.claude/statusline.sh
```

Restart Claude Code. That's it.

To remove: `claude config set statusLine.command ""`

## Under the Hood

Claude Code polls the statusline every ~300ms, so speed matters:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, duration, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits` (CC >= 2.1.80) | None needed (real-time) |
| Quota fallback | Anthropic Usage API (CC < 2.1.80) | `/tmp`, 300s TTL, async background refresh |
| Git branch + diff | `git` commands | `/tmp`, 5s TTL |

On Claude Code >= 2.1.80, usage data comes directly from stdin -- real-time, no network calls. On older versions, it falls back to the Usage API in a background subshell so the statusline never blocks.

## License

MIT
