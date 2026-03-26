# Claude Lens

Know your quota before you hit the wall. A statusline for Claude Code — single Bash file, zero npm.

Most statuslines show "you used 60%." That number means nothing without context. 60% with 30 minutes left? Fine, the window resets soon. 60% with 4 hours left? You're about to hit the wall. claude-lens compares your usage rate to the time remaining and shows the delta. No Node.js, no npm, no lock files. Single Bash file.

![claude-lens statusline demo](.github/claude-lens-demo.gif)

- **+15%** green = you've used 15% less than expected. Headroom. Keep going.
- **-15%** red = you're burning 15% faster than sustainable. Slow down.
- **15%** / **20%** = used in the 5h and 7d windows. **3h** = resets in 3 hours.
- Top line: model, effort, project `(branch)`, `3f +24 -7` = git diff stats

## Install

Requires `jq`.

**Plugin (recommended):**

Run in your terminal:

```bash
claude plugin marketplace add Astro-Han/claude-lens
claude plugin install claude-lens
```

Then inside Claude Code, type `/claude-lens:setup`.

**Manual:**

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh
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

## How It Compares

|  | claude-lens | Node.js/TypeScript statuslines | Rust/Go statuslines |
|---|---|---|---|
| Runtime | `jq` | Node.js 18+ / npm | Compiled binary |
| Codebase | Single file | 1000+ lines + node_modules | Compiled, not inspectable |
| Execution | ~10ms, 3% of refresh cycle | ~90ms, 30% of refresh cycle | ~5ms (est.) |
| Memory | ~2 MB | ~57 MB | ~3 MB (est.) |
| Failure modes | Read-only, worst case prints "Claude" | Runtime dependency, package manager | Generally stable |
| Pace tracking | Usage rate vs time remaining | Trend-only or none | None |

Execution and memory measured on Apple Silicon, 300 runs, same stdin JSON. Rust/Go values are estimates.

Need themes, powerline aesthetics, or TUI config? Try [ccstatusline](https://github.com/sirmalloc/ccstatusline). The entire source of claude-lens is [one file](claude-lens.sh). Read it.

## Under the Hood

Claude Code polls the statusline every ~300ms:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits` (CC >= 2.1.80) | None needed (real-time) |
| Quota fallback | Anthropic Usage API (CC < 2.1.80) | `/tmp`, 300s TTL, async background refresh |
| Git branch + diff | `git` commands | `/tmp`, 5s TTL |

On Claude Code >= 2.1.80, usage data comes directly from stdin. No network calls. On older versions, it falls back to the Usage API in a background subshell so the statusline never blocks.

## License

MIT
