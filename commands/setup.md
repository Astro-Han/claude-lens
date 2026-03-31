---
description: Install and configure claude-pace statusline
allowed-tools: Bash, Read, Write, Edit
---

# claude-pace Setup

You are setting up claude-pace, a lightweight statusline for Claude Code.

Follow these steps in order. If any step fails, stop and explain the issue to the user.

## Step 1: Check prerequisites

Run: `command -v jq`

If jq is not found, tell the user to install it (`brew install jq` on macOS, `apt install jq` on Linux) and stop.

## Step 2: Determine plugin install path

The plugin was installed via the Claude Code plugin system. Find the claude-pace.sh script within the plugin cache.

Run: `find ~/.claude/plugins/cache -path "*/claude-pace/*/claude-pace.sh" 2>/dev/null | head -1`

If found, save that path as SCRIPT_PATH.

If not found, fall back to downloading:
```bash
curl -fsSL -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-pace/main/claude-pace.sh
chmod +x ~/.claude/statusline.sh
```
Set SCRIPT_PATH to `~/.claude/statusline.sh`.

## Step 3: Ensure the script is executable

Run: `chmod +x <SCRIPT_PATH>`

## Step 4: Configure statusline

Read `~/.claude/settings.json` with the Read tool. Then use the Edit tool to add or update the `statusLine` key:

```json
"statusLine": {
  "type": "command",
  "command": "<SCRIPT_PATH>"
}
```

If `statusLine` already exists, update the `command` value. If it does not exist, add it as a top-level key.

## Step 5: Confirm

Tell the user:

- claude-pace has been configured successfully.
- Restart Claude Code (or start a new session) to see the statusline.
- To remove later: delete the `statusLine` block from `~/.claude/settings.json`.
