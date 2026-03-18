# Claude Lens

> A fast, lightweight statusline for Claude Code. Pure Bash + jq.

![claude-lens statusline](claude-lens-showcase.jpg)

## Install

```bash
claude --plugin https://github.com/Astro-Han/claude-lens
```

Activate the statusline:

```bash
lens=$(find ~/.claude/plugins -name 'claude-lens.sh' -type f 2>/dev/null | head -1) && bash "$lens" --install
```

Restart Claude Code. Done. If `find` returns nothing, the plugin may not be installed yet.

To remove: replace `--install` with `--uninstall`.

## Features

**Everything you need, nothing you don't:**

- Context progress bar with color thresholds and trend arrows
- Usage remaining (5h/7d) with reset countdowns
- **Pace tracking** - see reserve (+N%, green) or deficit (-N%, red) vs ideal consumption pace
- Git branch, changed files, lines added/deleted, ahead/behind
- Active tool, subagent status, todo progress
- Session duration, token output speed
- Worktree-aware path display

**Zero config required.** Sensible defaults out of the box.

## Configure

Edit `~/.config/claude-lens/config` (or `$CLAUDE_PLUGIN_DATA/config`):

```ini
# Preset: minimal | standard | full
PRESET=standard

# Module toggles (true/false)
SHOW_COST=false
SHOW_SPEED=true
SHOW_TREND=true
SHOW_USAGE=true
```

Changes take effect on the next statusline refresh (~300ms).

## vs claude-hud

[claude-hud](https://github.com/jarrodwatts/claude-hud) pioneered statusline monitoring for Claude Code. claude-lens matches its features and adds pace tracking, while solving a fundamental performance problem:

| | claude-hud | claude-lens |
|--|-----------|-------------|
| Runtime | Node.js (cold start every 300ms) | Bash + jq |
| Invocation | 150-300ms | ~50ms |
| Transcript | Full scan O(n) - degrades over time | Incremental O(1) - constant |
| Caching | In-memory (lost on restart) | File-based (survives restarts) |
| Usage API | Blocks on cache miss | Async background refresh |

Features only in claude-lens: pace tracking, remaining % display, both 5h+7d reset countdowns, diff line stats, worktree paths.

## How It Works

Claude Code calls the statusline script every ~300ms. claude-lens uses layered caching to stay fast:

- **stdin JSON** - context, model, duration (direct, no I/O)
- **Git** - file cache, TTL 5s
- **Usage API** - file cache, TTL 300s, async background refresh (stale-while-revalidate)
- **Transcript** - byte-offset tracking, only reads new data since last call

## License

MIT
