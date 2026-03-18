#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../../claude-lens.sh"

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.claude"
  export CLAUDE_LENS_SETTINGS="${TEST_DIR}/.claude/settings.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# === --install ===

@test "--install: creates settings.json when not exists" {
  run "$SCRIPT" --install
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_LENS_SETTINGS" ]
  run jq -r '.statusLine.type' "$CLAUDE_LENS_SETTINGS"
  [ "$output" = "command" ]
}

@test "--install: preserves existing settings" {
  echo '{"env":{"FOO":"bar"}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --install
  [ "$status" -eq 0 ]
  run jq -r '.env.FOO' "$CLAUDE_LENS_SETTINGS"
  [ "$output" = "bar" ]
  run jq -r '.statusLine.type' "$CLAUDE_LENS_SETTINGS"
  [ "$output" = "command" ]
}

@test "--install: command points to script's absolute path" {
  run "$SCRIPT" --install
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(jq -r '.statusLine.command' "$CLAUDE_LENS_SETTINGS")
  [[ "$cmd" == /* ]]
  [[ "$cmd" == *"claude-lens.sh" ]]
  [ -f "$cmd" ]
}

@test "--install: overwrites existing statusLine" {
  echo '{"statusLine":{"type":"command","command":"/old/path"}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --install
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(jq -r '.statusLine.command' "$CLAUDE_LENS_SETTINGS")
  [[ "$cmd" != "/old/path" ]]
}

@test "--install: outputs success message" {
  run "$SCRIPT" --install
  [ "$status" -eq 0 ]
  [[ "$output" == *"activated"* ]]
}

# === --uninstall ===

@test "--uninstall: removes statusLine from settings" {
  echo '{"statusLine":{"type":"command","command":"/some/path"},"env":{}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  run jq 'has("statusLine")' "$CLAUDE_LENS_SETTINGS"
  [ "$output" = "false" ]
}

@test "--uninstall: preserves other settings" {
  echo '{"statusLine":{"type":"command","command":"/p"},"env":{"X":"1"}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  run jq -r '.env.X' "$CLAUDE_LENS_SETTINGS"
  [ "$output" = "1" ]
}

@test "--uninstall: no-op when settings.json missing" {
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"deactivated"* ]]
}

@test "--uninstall: no-op when no statusLine key" {
  echo '{"env":{}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_LENS_SETTINGS" ]
}

@test "--uninstall: outputs deactivated message" {
  echo '{"statusLine":{"type":"command","command":"/p"}}' > "$CLAUDE_LENS_SETTINGS"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"deactivated"* ]]
}
