#!/usr/bin/env node

// One-step installer for claude-pace statusline.
// Copies the Bash script to ~/.claude/ and configures settings.json.
// After install, Node is not needed. The statusline runs as pure Bash + jq.

const { execSync } = require("child_process");
const { readFileSync, writeFileSync, copyFileSync, chmodSync, renameSync, existsSync, mkdirSync } = require("fs");
const { join } = require("path");
const { homedir, platform } = require("os");

// Platform guard: statusline is Bash, won't run on Windows
if (platform() === "win32") {
  console.error("Error: claude-pace requires Bash and only works on macOS/Linux.");
  process.exit(1);
}

// Check jq dependency
try {
  execSync("command -v jq", { stdio: "ignore" });
} catch {
  console.error("Error: jq is required but not found.");
  console.error("Install it: brew install jq (macOS) or apt install jq (Linux)");
  process.exit(1);
}

const claudeDir = join(homedir(), ".claude");
const dest = join(claudeDir, "statusline.sh");
const settingsPath = join(claudeDir, "settings.json");

// Ensure ~/.claude/ exists
if (!existsSync(claudeDir)) {
  mkdirSync(claudeDir, { recursive: true });
}

// Copy statusline script and make it executable
copyFileSync(join(__dirname, "claude-pace.sh"), dest);
chmodSync(dest, 0o755);

// Read existing settings (empty file treated as fresh)
let settings = {};
if (existsSync(settingsPath)) {
  const raw = readFileSync(settingsPath, "utf8").trim();
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      // settings.json must be a plain object
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        settings = parsed;
      } else {
        console.error("Error: ~/.claude/settings.json is not a JSON object. Fix it manually, then re-run.");
        process.exit(1);
      }
    } catch {
      console.error("Error: ~/.claude/settings.json is not valid JSON. Fix it manually, then re-run.");
      process.exit(1);
    }
  }
}

// Merge statusLine config (spread preserves any future sub-fields)
const updating = settings.statusLine && settings.statusLine.command;
settings.statusLine = { ...settings.statusLine, type: "command", command: "~/.claude/statusline.sh" };

// Atomic write: tmp file + rename to prevent truncation on crash
const tmp = settingsPath + ".tmp";
writeFileSync(tmp, JSON.stringify(settings, null, 2) + "\n");
renameSync(tmp, settingsPath);

console.log(updating ? "claude-pace updated. Restart Claude Code." : "claude-pace installed. Restart Claude Code to see the statusline.");
