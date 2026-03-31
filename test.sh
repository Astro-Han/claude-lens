#!/usr/bin/env bash
# Regression tests for claude-pace statusline
# Usage: bash test.sh
set -euo pipefail

PASS=0 FAIL=0
strip_ansi() { perl -pe 's/\e\[[0-9;]*m//g'; }
TEST_TMP=$(mktemp -d)
USAGE_ARITH_MARKER="/tmp/claudepaceusagearith$$"
cleanup_test_artifacts() {
  rm -f "$USAGE_ARITH_MARKER"
  rm -rf "$TEST_TMP"
}
trap cleanup_test_artifacts EXIT

assert_line() {
  local name="$1" line_num="$2" pattern="$3" actual
  actual=$(echo "$OUTPUT" | sed -n "${line_num}p")
  if [[ "$actual" =~ $pattern ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected pattern: $pattern"
    echo "    actual:           $actual"
  fi
}

# Pipe alignment check: | must be at same column on both lines
assert_aligned() {
  local name="$1"
  local col1 col2 l1 l2
  l1=$(echo "$OUTPUT" | sed -n '1p') l2=$(echo "$OUTPUT" | sed -n '2p')
  col1=${l1%%|*} col2=${l2%%|*}
  col1=${#col1} col2=${#col2}
  if [[ "$col1" == "$col2" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name (col $col1)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (L1=$col1 L2=$col2)"
  fi
}

assert_missing_path() {
  local name="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    path exists: $path"
  fi
}

assert_line_count() {
  local name="$1" expected="$2" actual
  actual=$(printf '%s\n' "$OUTPUT" | wc -l | tr -d ' ')
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected line count: $expected"
    echo "    actual line count:   $actual"
  fi
}

NOW=$(date +%s)
REPO_NAME=$(basename "$PWD")
run() { echo "$1" | bash claude-pace.sh 2>/dev/null | strip_ansi; }
invoke_with_env() {
  local home_dir="$1" runtime_dir="$2" input="$3"
  env HOME="$home_dir" XDG_RUNTIME_DIR="$runtime_dir" USER=tester PATH="$PATH" \
    bash claude-pace.sh 2>/dev/null <<<"$input"
}
run_with_env() {
  invoke_with_env "$1" "$2" "$3" | strip_ansi
}
run_side_effect_with_env() {
  invoke_with_env "$1" "$2" "$3" >/dev/null
}
invoke_with_env_and_path() {
  local home_dir="$1" runtime_dir="$2" path_dir="$3" input="$4"
  env HOME="$home_dir" XDG_RUNTIME_DIR="$runtime_dir" USER=tester PATH="$path_dir:$PATH" \
    CLAUDE_CODE_OAUTH_TOKEN=fake-token bash claude-pace.sh 2>/dev/null <<<"$input"
}
run_with_env_and_path() {
  invoke_with_env_and_path "$1" "$2" "$3" "$4" | strip_ansi
}
run_side_effect_with_env_and_path() {
  invoke_with_env_and_path "$1" "$2" "$3" "$4" >/dev/null
}

git_cache_path_for_dir() {
  local dir="$1"
  printf '/tmp/claude-sl-git-%s\n' "${dir//[^a-zA-Z0-9]/_}"
}

init_test_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -b main >/dev/null 2>&1
  git -C "$repo_dir" config user.name tester
  git -C "$repo_dir" config user.email tester@example.com
  printf 'ok\n' >"$repo_dir/readme.txt"
  git -C "$repo_dir" add readme.txt
  git -C "$repo_dir" commit -m init >/dev/null 2>&1
}

# ── Test 1: MODEL_SHORT strips "(1M context)" → "(1M)" ──
echo "Test 1: MODEL_SHORT"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":16,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":'$((NOW + 2580))'},"seven_day":{"used_percentage":21,"resets_at":'$((NOW + 345600))'}}}')
assert_line "model shows (1M) not (1M context)" 1 'Opus 4\.6 \(1M\)'
assert_line "no brackets around model" 1 '^Opus'

# ── Test 2: Model without context in name gets (CL) appended ──
echo "Test 2: MODEL_SHORT append"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":50,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":57,"resets_at":'$((NOW + 7200))'},"seven_day":{"used_percentage":35,"resets_at":'$((NOW + 432000))'}}}')
assert_line "appends (200K)" 1 'Sonnet 4\.6 \(200K\)'

# ── Test 3: CTX=0 should NOT append "(0K)" ──
echo "Test 3: CTX=0 guard"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":0,"context_window_size":0}}')
assert_line "no (0K) in model" 1 '^Opus 4\.6 [^(]'

# ── Test 4: Branch in parentheses ──
echo "Test 4: branch format"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":16,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":'$((NOW + 2580))'},"seven_day":{"used_percentage":21,"resets_at":'$((NOW + 345600))'}}}')
assert_line "branch in parens (main)" 1 '\(main\)'
assert_line "project name only" 1 "$REPO_NAME"

# ── Test 5: Pipe alignment ──
echo "Test 5: pipe alignment"
assert_aligned "| aligned between lines"

# ── Test 6: Line 2 format - single pipe, no colons, no parens on countdown ──
echo "Test 6: line 2 format"
assert_line "single pipe on L2" 2 '^[^|]+\|[^|]*$'
assert_line "no colon after 5h" 2 '5h [0-9]'
assert_line "no colon after 7d" 2 '7d [0-9]'
assert_line "no parens on countdown" 2 '[0-9]+[dhm][^)]'
assert_line "no 'of' before context size" 2 '^[^ ]+ [0-9]+% [0-9]+[MK] '

# ── Test 7: Different model alignment ──
echo "Test 7: Sonnet alignment"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":50,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":57,"resets_at":'$((NOW + 7200))'},"seven_day":{"used_percentage":35,"resets_at":'$((NOW + 432000))'}}}')
assert_aligned "| aligned for Sonnet"

# ── Test 8: 100% context alignment ──
echo "Test 8: 100% context alignment"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":100,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":92,"resets_at":'$((NOW + 600))'},"seven_day":{"used_percentage":79,"resets_at":'$((NOW + 172800))'}}}')
assert_aligned "| aligned at 100%"

# ── Test 9: Worktree path ──
echo "Test 9: worktree"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'/.claude/worktrees/fix-auth"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$((NOW + 12000))'},"seven_day":{"used_percentage":15,"resets_at":'$((NOW + 500000))'}}}')
assert_line "worktree shows repo name" 1 "$REPO_NAME"

# ── Test 10: Long model name truncation ──
echo "Test 10: long model truncation"
OUTPUT=$(run '{"model":{"display_name":"claude-3-opus-20240229-extended"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":25,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":'$((NOW + 14000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 500000))'}}}')
assert_aligned "| aligned for long model"

# ── Test 11: Pace delta arrows (small values must show after threshold removal) ──
echo "Test 11: pace delta"
# 5h window=300min, resets_at=NOW+150min → expected=50%.
# used=51 → d=+1 (⇡1%, minimum positive boundary)
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":51,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "⇡1% shown for min overspend" 2 '5h 51% ⇡1%'
# used=49 → d=-1 (⇣1%, minimum negative boundary)
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":49,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "⇣1% shown for min surplus" 2 '5h 49% ⇣1%'
# used=50 → d=0 (no arrow on 5h). 7d also d=0 so no arrow anywhere.
# 7d window=10080min, resets_at=NOW+302400s=5040min → expected=(10080-5040)*100/10080=50
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "no arrow at d=0" 2 '5h 50% [0-9]'

# ── Test 12: Branch cache must not inject newlines into output ──
echo "Test 12: branch cache newline injection"
INJECT_HOME="$TEST_TMP/inject-home"
INJECT_RUNTIME="$TEST_TMP/inject-runtime"
INJECT_DIR="$TEST_TMP/non-git-escape"
INJECT_CACHE_ROOT="$INJECT_RUNTIME/claude-pace"
mkdir -p "$INJECT_HOME" "$INJECT_RUNTIME" "$INJECT_DIR" "$INJECT_CACHE_ROOT"
GC="$INJECT_CACHE_ROOT/claude-sl-git-${INJECT_DIR//[^a-zA-Z0-9]/_}"
printf 'feature\\nPWN|0|0|0\n' >"$GC"
OUTPUT=$(run_with_env "$INJECT_HOME" "$INJECT_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$INJECT_DIR"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
assert_line_count "branch cache keeps output to two lines" 2

# ── Test 13: Git cache arithmetic payload must not execute ──
echo "Test 13: git cache arithmetic injection"
INJECT_GIT_HOME="$TEST_TMP/non-git-arith-home"
INJECT_GIT_RUNTIME="$TEST_TMP/non-git-arith-runtime"
INJECT_GIT_DIR="$TEST_TMP/non-git-arith"
INJECT_GIT_CACHE_ROOT="$INJECT_GIT_RUNTIME/claude-pace"
mkdir -p "$INJECT_GIT_HOME" "$INJECT_GIT_RUNTIME" "$INJECT_GIT_DIR" "$INJECT_GIT_CACHE_ROOT"
GC="$INJECT_GIT_CACHE_ROOT/claude-sl-git-${INJECT_GIT_DIR//[^a-zA-Z0-9]/_}"
GIT_MARKER="$TEST_TMP/git-arith-marker"
FC_PAYLOAD="a[\$(printf git >$GIT_MARKER)]"
printf 'main|%s|0|0\n' "$FC_PAYLOAD" >"$GC"
run_side_effect_with_env "$INJECT_GIT_HOME" "$INJECT_GIT_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$INJECT_GIT_DIR"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git cache arithmetic payload is not executed" "$GIT_MARKER"

# ── Test 14: Usage cache arithmetic payload must not execute ──
echo "Test 14: usage cache arithmetic injection"
USAGE_HOME="$TEST_TMP/usage-arith-home"
USAGE_RUNTIME="$TEST_TMP/usage-arith-runtime"
USAGE_CACHE_ROOT="$USAGE_RUNTIME/claude-pace"
mkdir -p "$USAGE_HOME" "$USAGE_RUNTIME" "$USAGE_CACHE_ROOT"
XU_PAYLOAD="a[\$(printf usage >$USAGE_ARITH_MARKER)]"
printf '%s\n' "--|--|1|$XU_PAYLOAD|0||" >"$USAGE_CACHE_ROOT/claude-sl-usage"
run_side_effect_with_env "$USAGE_HOME" "$USAGE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000}}'
assert_missing_path "usage cache arithmetic payload is not executed" "$USAGE_ARITH_MARKER"

# ── Test 15: Shared /tmp git cache must be ignored when using a private cache root ──
echo "Test 15: private cache root ignores shared tmp git cache"
PRIVATE_HOME="$TEST_TMP/private-home"
PRIVATE_RUNTIME="$TEST_TMP/private-runtime"
PRIVATE_REPO="$TEST_TMP/private-repo"
mkdir -p "$PRIVATE_HOME" "$PRIVATE_RUNTIME"
init_test_repo "$PRIVATE_REPO"
GC=$(git_cache_path_for_dir "$PRIVATE_REPO")
printf 'evil|0|0|0\n' >"$GC"
OUTPUT=$(run_with_env "$PRIVATE_HOME" "$PRIVATE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PRIVATE_REPO"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
if [[ "$OUTPUT" =~ \(main\) ]] && [[ ! "$OUTPUT" =~ \(evil\) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: private cache root ignores poisoned shared tmp cache"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: private cache root ignores poisoned shared tmp cache"
  echo "    actual line: $(printf '%s\n' "$OUTPUT" | sed -n '1p')"
fi

# ── Test 16: Cache format must preserve branch names that contain | ──
echo "Test 16: branch names containing pipes survive cache round-trip"
PIPE_HOME="$TEST_TMP/pipe-home"
PIPE_RUNTIME="$TEST_TMP/pipe-runtime"
PIPE_REPO="$TEST_TMP/pipe-repo"
mkdir -p "$PIPE_HOME" "$PIPE_RUNTIME"
init_test_repo "$PIPE_REPO"
git -C "$PIPE_REPO" checkout -b 'feat|pipe' >/dev/null 2>&1
OUTPUT=$(run_with_env "$PIPE_HOME" "$PIPE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PIPE_REPO"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
if [[ "$OUTPUT" =~ \(feat\|pipe\) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: cache preserves branch names containing pipes"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: cache preserves branch names containing pipes"
  echo "    actual line: $(printf '%s\n' "$OUTPUT" | sed -n '1p')"
fi

# ── Test 17: Git fallback write must not follow symlinks ──
echo "Test 17: git fallback does not clobber symlink targets"
SYMLINK_HOME="$TEST_TMP/symlink-home"
SYMLINK_RUNTIME="$TEST_TMP/symlink-runtime"
SYMLINK_PROJECT="$TEST_TMP/symlink-project"
SYMLINK_CACHE_ROOT="$SYMLINK_RUNTIME/claude-pace"
SYMLINK_TARGET="$TEST_TMP/git-fallback-target"
mkdir -p "$SYMLINK_HOME" "$SYMLINK_RUNTIME" "$SYMLINK_PROJECT" "$SYMLINK_CACHE_ROOT"
GC="$SYMLINK_CACHE_ROOT/claude-sl-git-${SYMLINK_PROJECT//[^a-zA-Z0-9]/_}"
ln -s "$SYMLINK_TARGET" "$GC"
run_side_effect_with_env "$SYMLINK_HOME" "$SYMLINK_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$SYMLINK_PROJECT"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git fallback leaves symlink target untouched" "$SYMLINK_TARGET"

# ── Test 18: Usage fallback write must not follow symlinks ──
echo "Test 18: usage fallback does not clobber symlink targets"
USAGE_HOME="$TEST_TMP/usage-home"
USAGE_RUNTIME="$TEST_TMP/usage-runtime"
FAKE_BIN="$TEST_TMP/fake-bin"
USAGE_CACHE_ROOT="$USAGE_RUNTIME/claude-pace"
USAGE_TARGET="$TEST_TMP/usage-fallback-target"
mkdir -p "$USAGE_HOME" "$USAGE_RUNTIME" "$FAKE_BIN" "$USAGE_CACHE_ROOT"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'not-json\n'
EOF
chmod +x "$FAKE_BIN/curl"
UC_PATH="$USAGE_CACHE_ROOT/claude-sl-usage"
UL_PATH="$USAGE_CACHE_ROOT/claude-sl-usage.lock"
ln -s "$USAGE_TARGET" "$UC_PATH"
run_side_effect_with_env_and_path "$USAGE_HOME" "$USAGE_RUNTIME" "$FAKE_BIN" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000}}'
for _ in 1 2 3 4 5; do
  [[ -e "$USAGE_TARGET" ]] && break
  sleep 0.2
done
assert_missing_path "usage fallback leaves symlink target untouched" "$USAGE_TARGET"
[ -e "$UL_PATH" ] && rm -f "$UL_PATH"

# ── Test 19: No-cache mode must still fetch usage API data ──
echo "Test 19: no-cache mode still fetches usage API"
NO_CACHE_FAKE_BIN="$TEST_TMP/no-cache-fake-bin"
mkdir -p "$NO_CACHE_FAKE_BIN"
cat >"$NO_CACHE_FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"five_hour":{"utilization":11,"resets_at":"2030-01-01T01:00:00Z"},"seven_day":{"utilization":22,"resets_at":"2030-01-07T01:00:00Z"},"extra_usage":{"is_enabled":true,"used_credits":123,"monthly_limit":500}}
JSON
EOF
chmod +x "$NO_CACHE_FAKE_BIN/curl"
OUTPUT=$(run_with_env_and_path "/dev/null" "" "$NO_CACHE_FAKE_BIN" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "no-cache mode still shows fetched 5h usage" 2 '5h 11%'
assert_line "no-cache mode still shows fetched 7d usage" 2 '7d 22%'

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
