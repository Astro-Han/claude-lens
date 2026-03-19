# Claude Lens

> Know if you're burning through your Claude Code quota too fast. Pure Bash + jq, 158 lines.

![claude-lens statusline](.github/claude-lens-showcase.jpg)

## Install

```bash
# Download
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh

# Register as Claude Code statusline
claude config set statusLine.command ~/.claude/statusline.sh
```

Restart Claude Code. Done.

To remove: `claude config set statusLine.command ""`

## What You See

```
[Opus 4.6 ●] ~/project | main 3f +42 -7
████████░░ 80% of 1M | 5h: 65%↑5 | 7d: 42% | 2h13m
```

**Line 1:** Model, effort level, directory, git branch + diff stats

**Line 2:** Context bar, 5h/7d usage with delta arrows, session duration

- Color-coded usage: green (<70%), yellow (70-89%), red (>=90%)
- Delta arrows show change since last API fetch (↑5 = rose 5% since last check)
- Extra usage costs shown when near limit
- Worktree paths auto-shortened

Zero config. No dependencies beyond `jq`.

## How It Works

Claude Code calls the statusline script every ~300ms. claude-lens uses layered caching to stay fast:

- **stdin JSON** - context, model, duration, cost (direct parse, no I/O)
- **Git** - file cache in `/tmp`, TTL 5s
- **Usage API** - file cache, TTL 300s, async background refresh (stale-while-revalidate)

The entire script runs in a single process with one `jq` call for stdin parsing. Usage API fetches happen in a background subshell so the statusline never blocks.

## License

MIT
