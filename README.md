# Claude Lens

Know your quota before you hit the wall. A statusline for Claude Code in ~165 lines of Bash + jq.

Most statuslines show "you used 60%." That number means nothing without context. 60% with 4 hours left? Fine. 60% with 30 minutes left? You're about to hit the wall. claude-lens compares your usage rate to the time remaining and shows the delta. No Node.js, no npm, no lock files. Single Bash file.

![claude-lens showing 92% quota remaining with +17% pace delta](.github/claude-lens-showcase.png)

- **+17%** green = you've used 17% less than expected. Headroom. Keep going.
- **92%** / **29%** = remaining in the 5h and 7d windows. **(3h)** = resets in 3 hours.
- Top line: model, effort, context %, project, git branch `+N -N`

## Install

Requires `jq`.

**Plugin (recommended):**

```
/plugin marketplace add Astro-Han/claude-lens
/plugin install claude-lens
/claude-lens:setup
```

**Manual:**

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh
chmod +x ~/.claude/statusline.sh

claude config set statusLine.command ~/.claude/statusline.sh
```

Restart Claude Code. Done.

To remove: `claude config set statusLine.command ""`

## How It Compares

|  | claude-lens | Node.js/TypeScript statuslines | Rust/Go statuslines |
|---|---|---|---|
| Runtime | `jq` | Node.js 18+ / npm | Compiled binary |
| Codebase | ~165 lines, single file | 1000+ lines + node_modules | Compiled, not inspectable |
| Failure modes | Read-only, worst case prints "Claude" | Runtime dependency, package manager | Generally stable |
| Pace tracking | Usage rate vs time remaining | Trend-only or none | None |

Need themes, powerline aesthetics, or TUI config? Try [ccstatusline](https://github.com/sirmalloc/ccstatusline). The entire source of claude-lens is [one file](claude-lens.sh). Read it.

## Under the Hood

Claude Code polls the statusline every ~300ms:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, duration, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits` (CC >= 2.1.80) | None needed (real-time) |
| Quota fallback | Anthropic Usage API (CC < 2.1.80) | `/tmp`, 300s TTL, async background refresh |
| Git branch + diff | `git` commands | `/tmp`, 5s TTL |

On Claude Code >= 2.1.80, usage data comes directly from stdin. No network calls. On older versions, it falls back to the Usage API in a background subshell so the statusline never blocks.

## License

MIT
