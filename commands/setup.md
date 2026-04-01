---
description: Install or update claude-pace statusline
allowed-tools: Bash, Read, Write, Edit
---

# claude-pace Setup

You are installing or updating claude-pace, a lightweight statusline for Claude Code.
This skill is idempotent: safe to run for both first install and subsequent updates.

Follow these steps in order. If any step fails, stop and explain the issue to the user.

## Step 1: Check prerequisites

Run: `command -v jq`

If jq is not found, tell the user to install it (`brew install jq` on macOS, `apt install jq` on Linux) and stop.

## Step 2: Download the latest script

Always fetch from the main branch to get the latest version:

```bash
curl -fsSL -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-pace/main/claude-pace.sh
chmod +x ~/.claude/statusline.sh
```

## Step 3: Configure statusline

Read `~/.claude/settings.json` with the Read tool. Then use the Edit tool to add or update the `statusLine` key:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh"
}
```

If `statusLine` already exists, update the `command` value. If it does not exist, add it as a top-level key.

## Step 4: Confirm

Tell the user:

- claude-pace has been installed (or updated) successfully.
- Restart Claude Code (or start a new session) to see the statusline.
- To update later: run `/claude-pace:setup` again.
- To remove: delete the `statusLine` block from `~/.claude/settings.json`.
