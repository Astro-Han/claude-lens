#!/usr/bin/env bash
# Regression tests for claude-pace statusline
# Usage: bash test.sh
# shellcheck disable=SC2016  # regex literals like '\$1\.23' intentionally use single quotes
set -euo pipefail

PASS=0 FAIL=0
strip_ansi() { perl -pe 's/\e\[[0-9;]*m//g'; }
TEST_TMP=$(mktemp -d)
# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup_test_artifacts() {
  rm -rf "$TEST_TMP"
}
trap cleanup_test_artifacts EXIT

OUTPUT=""

output_line() {
  local line_num="$1"
  printf '%s\n' "$OUTPUT" | sed -n "${line_num}p"
}

assert_line_match() {
  local name="$1" line_num="$2" pattern="$3" expect_match="$4" actual matched
  actual=$(output_line "$line_num")
  if [[ "$actual" =~ $pattern ]]; then
    matched=1
  else
    matched=0
  fi
  if [[ "$matched" == "$expect_match" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    if [[ "$expect_match" == "1" ]]; then
      echo "    expected pattern: $pattern"
      echo "    actual:           $actual"
    else
      echo "    unexpected pattern: $pattern"
      echo "    actual:             $actual"
    fi
  fi
}

assert_line() {
  assert_line_match "$1" "$2" "$3" 1
}

assert_line_not() {
  assert_line_match "$1" "$2" "$3" 0
}

# Pipe alignment check: | must be at same column on both lines
assert_aligned() {
  local name="$1"
  local col1 col2 l1 l2
  l1=$(output_line 1)
  l2=$(output_line 2)
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
CURRENT_BRANCH=$(git branch --show-current)
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

_hash_dir() { printf '%s' "$1" | { shasum 2>/dev/null || sha1sum; } | cut -c1-16; }
git_cache_path_for_dir() {
  local dir="$1"
  printf '/tmp/claude-sl-git-%s\n' "$(_hash_dir "$dir")"
}

quota_cache_path_for_root() {
  local cache_root="$1"
  printf '%s/claude-sl-quota\n' "$cache_root"
}

run_without_safe_cache_root() {
  local input="$1"
  env HOME="/dev/null" XDG_RUNTIME_DIR="" USER=tester PATH="$PATH" \
    bash claude-pace.sh 2>/dev/null <<<"$input"
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
if [[ -n "$CURRENT_BRANCH" ]]; then
  assert_line "branch in parens ($CURRENT_BRANCH)" 1 "\\($CURRENT_BRANCH\\)"
else
  assert_line "no branch suffix in detached HEAD" 1 "\\|  $REPO_NAME$"
fi
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
GC="$INJECT_CACHE_ROOT/claude-sl-git-$(_hash_dir "$INJECT_DIR")"
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
GC="$INJECT_GIT_CACHE_ROOT/claude-sl-git-$(_hash_dir "$INJECT_GIT_DIR")"
GIT_MARKER="$TEST_TMP/git-arith-marker"
FC_PAYLOAD="a[\$(printf git >$GIT_MARKER)]"
printf 'main|%s|0|0\n' "$FC_PAYLOAD" >"$GC"
run_side_effect_with_env "$INJECT_GIT_HOME" "$INJECT_GIT_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$INJECT_GIT_DIR"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git cache arithmetic payload is not executed" "$GIT_MARKER"

# ── Test 14: Shared /tmp git cache must be ignored when using a private cache root ──
echo "Test 14: private cache root ignores shared tmp git cache"
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

# ── Test 15: Cache format must preserve branch names that contain | ──
echo "Test 15: branch names containing pipes survive cache round-trip"
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

# ── Test 16: Git fallback write must not follow symlinks ──
echo "Test 16: git fallback does not clobber symlink targets"
SYMLINK_HOME="$TEST_TMP/symlink-home"
SYMLINK_RUNTIME="$TEST_TMP/symlink-runtime"
SYMLINK_PROJECT="$TEST_TMP/symlink-project"
SYMLINK_CACHE_ROOT="$SYMLINK_RUNTIME/claude-pace"
SYMLINK_TARGET="$TEST_TMP/git-fallback-target"
mkdir -p "$SYMLINK_HOME" "$SYMLINK_RUNTIME" "$SYMLINK_PROJECT" "$SYMLINK_CACHE_ROOT"
GC="$SYMLINK_CACHE_ROOT/claude-sl-git-$(_hash_dir "$SYMLINK_PROJECT")"
ln -s "$SYMLINK_TARGET" "$GC"
run_side_effect_with_env "$SYMLINK_HOME" "$SYMLINK_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$SYMLINK_PROJECT"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git fallback leaves symlink target untouched" "$SYMLINK_TARGET"

# ── Test 17: Hash cache key prevents old-style path collisions ──
echo "Test 17: hash cache key collision resistance"
COLL_HOME="$TEST_TMP/coll-home"
COLL_RUNTIME="$TEST_TMP/coll-runtime"
COLL_CACHE_ROOT="$COLL_RUNTIME/claude-pace"
mkdir -p "$COLL_HOME" "$COLL_RUNTIME" "$COLL_CACHE_ROOT"
# These two dirs would collide under the old ${DIR//[^a-zA-Z0-9]/_} scheme
DIR_A="$TEST_TMP/coll-a/b"
DIR_B="$TEST_TMP/coll-a-b"
mkdir -p "$DIR_A" "$DIR_B"
HASH_A=$(_hash_dir "$DIR_A")
HASH_B=$(_hash_dir "$DIR_B")
if [[ "$HASH_A" != "$HASH_B" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: different dirs produce different cache keys"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: different dirs produce different cache keys"
  echo "    dir_a=$DIR_A hash=$HASH_A"
  echo "    dir_b=$DIR_B hash=$HASH_B"
fi

# ── Test 18: No rate_limits should not call Usage API ──
echo "Test 18: no rate_limits skips usage api"
NO_RL_BIN="$TEST_TMP/no-rate-limits-bin"
NO_RL_MARKER="$TEST_TMP/no-rate-limits-marker"
mkdir -p "$NO_RL_BIN"
cat >"$NO_RL_BIN/curl" <<EOF
#!/usr/bin/env bash
printf 'called\n' >"$NO_RL_MARKER"
printf 'not-json\n'
EOF
chmod +x "$NO_RL_BIN/curl"
OUTPUT=$(env HOME="/dev/null" XDG_RUNTIME_DIR="" USER=tester PATH="$NO_RL_BIN:$PATH" \
  CLAUDE_CODE_OAUTH_TOKEN=fake-token \
  bash claude-pace.sh 2>/dev/null <<<"$(
    cat <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}
JSON
  )" | strip_ansi)
assert_missing_path "curl not invoked when rate_limits missing" "$NO_RL_MARKER"
# shellcheck disable=SC2016  # single quotes intentional: regex pattern, not expansion
assert_line "session cost shown when rate_limits missing" 2 '\$1\.23'

# ── Test 19: Live rate_limits writes quota cache ──
echo "Test 19: live rate_limits writes quota cache"
QUOTA_HOME="$TEST_TMP/quota-home"
QUOTA_RUNTIME="$TEST_TMP/quota-runtime"
QUOTA_CACHE_ROOT="$QUOTA_RUNTIME/claude-pace"
mkdir -p "$QUOTA_HOME" "$QUOTA_RUNTIME"
run_side_effect_with_env "$QUOTA_HOME" "$QUOTA_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
QC=$(quota_cache_path_for_root "$QUOTA_CACHE_ROOT")
if [[ -f "$QC" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: quota cache file created from live rate_limits"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: quota cache file created from live rate_limits"
  echo "    missing path: $QC"
fi

# ── Test 20: Missing rate_limits reuses cached quota and suppresses cost ──
echo "Test 20: missing rate_limits reuses cached quota"
OUTPUT=$(run_with_env "$QUOTA_HOME" "$QUOTA_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "cached 5h quota shown" 2 '5h 30%'
assert_line "cached 7d quota shown" 2 '7d 15%'
assert_line_not "cached quota suppresses session cost" 2 '\$1\.23'

# ── Test 21: Invalid quota cache degrades to no-quota fallback ──
echo "Test 21: invalid quota cache degrades cleanly"
BAD_HOME="$TEST_TMP/bad-home"
BAD_RUNTIME="$TEST_TMP/bad-runtime"
BAD_CACHE_ROOT="$BAD_RUNTIME/claude-pace"
mkdir -p "$BAD_HOME" "$BAD_RUNTIME" "$BAD_CACHE_ROOT"
QC=$(quota_cache_path_for_root "$BAD_CACHE_ROOT")
printf 'abc|15|9999999999|9999999999\n' >"$QC"
OUTPUT=$(run_with_env "$BAD_HOME" "$BAD_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "invalid cache falls back to no quota 5h" 2 '5h --'
assert_line "invalid cache falls back to no quota 7d" 2 '7d --'
assert_line "invalid cache keeps session cost" 2 '\$1\.23'

# ── Test 22: Safe cache root with no quota file degrades to no-quota fallback ──
echo "Test 22: safe cache root without quota cache file"
EMPTY_HOME="$TEST_TMP/empty-home"
EMPTY_RUNTIME="$TEST_TMP/empty-runtime"
mkdir -p "$EMPTY_HOME" "$EMPTY_RUNTIME"
OUTPUT=$(run_with_env "$EMPTY_HOME" "$EMPTY_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "safe cache root without file keeps 5h --" 2 '5h --'
assert_line "safe cache root without file keeps 7d --" 2 '7d --'
assert_line "safe cache root without file keeps session cost" 2 '\$1\.23'

# ── Test 23: Partial live payload missing five_hour does not overwrite cache ──
echo "Test 23: partial live missing five_hour"
PARTIAL_HOME="$TEST_TMP/partial-home"
PARTIAL_RUNTIME="$TEST_TMP/partial-runtime"
mkdir -p "$PARTIAL_HOME" "$PARTIAL_RUNTIME"
run_side_effect_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23},"rate_limits":{"seven_day":{"used_percentage":18,"resets_at":'"$((NOW + 400000))"'}}}')
assert_line "partial live missing five_hour renders 5h --" 2 '5h --'
assert_line "partial live keeps live seven_day" 2 '7d 18%'
assert_line_not "partial live does not show session cost" 2 '\$1\.23'
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "cache survives missing five_hour partial live" 2 '5h 30%'
assert_line "cache keeps original seven_day after missing five_hour partial live" 2 '7d 15%'

# ── Test 24: Partial live payload missing five_hour.resets_at does not overwrite cache ──
echo "Test 24: partial live missing five_hour resets_at"
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":18,"resets_at":'"$((NOW + 400000))"'}}}')
assert_line "partial live missing five_hour resets_at keeps 5h percent" 2 '5h 31%'
assert_line_not "partial live missing five_hour resets_at hides cost" 2 '\$1\.23'
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "cache survives missing five_hour resets_at" 2 '5h 30%'
assert_line "cache keeps original seven_day after missing five_hour resets_at" 2 '7d 15%'

# ── Test 25: Partial live payload missing seven_day does not overwrite cache ──
echo "Test 25: partial live missing seven_day"
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23},"rate_limits":{"five_hour":{"used_percentage":29,"resets_at":'"$((NOW + 11000))"'}}}')
assert_line "partial live keeps live five_hour" 2 '5h 29%'
assert_line "partial live missing seven_day renders 7d --" 2 '7d --'
assert_line_not "partial live missing seven_day hides cost" 2 '\$1\.23'
OUTPUT=$(run_with_env "$PARTIAL_HOME" "$PARTIAL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "cache keeps original five_hour after missing seven_day partial live" 2 '5h 30%'
assert_line "cache survives missing seven_day partial live" 2 '7d 15%'

# ── Test 26: Expired live snapshot does not overwrite a good cache ──
echo "Test 26: expired live snapshot does not overwrite cache"
LIVE_EXPIRED_HOME="$TEST_TMP/live-expired-home"
LIVE_EXPIRED_RUNTIME="$TEST_TMP/live-expired-runtime"
mkdir -p "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME"
run_side_effect_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
run_side_effect_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":'"$NOW"'},"seven_day":{"used_percentage":66,"resets_at":'"$((NOW + 400000))"'}}}'
OUTPUT=$(run_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "expired live R5 keeps cached five_hour" 2 '5h 30%'
assert_line "expired live R5 keeps cached seven_day" 2 '7d 15%'
run_side_effect_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
run_side_effect_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":66,"resets_at":'"$((NOW + 11000))"'},"seven_day":{"used_percentage":99,"resets_at":'"$NOW"'}}}'
OUTPUT=$(run_with_env "$LIVE_EXPIRED_HOME" "$LIVE_EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "expired live R7 keeps cached five_hour" 2 '5h 30%'
assert_line "expired live R7 keeps cached seven_day" 2 '7d 15%'

# ── Test 27: Expired quota cache is rejected ──
echo "Test 27: expired quota cache is rejected"
EXPIRED_HOME="$TEST_TMP/expired-home"
EXPIRED_RUNTIME="$TEST_TMP/expired-runtime"
EXPIRED_CACHE_ROOT="$EXPIRED_RUNTIME/claude-pace"
mkdir -p "$EXPIRED_HOME" "$EXPIRED_RUNTIME" "$EXPIRED_CACHE_ROOT"
QC=$(quota_cache_path_for_root "$EXPIRED_CACHE_ROOT")
printf '30|15|%s|%s\n' "$NOW" "$((NOW + 500000))" >"$QC"
OUTPUT=$(run_with_env "$EXPIRED_HOME" "$EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "expired R5 rejects whole snapshot" 2 '5h --'
assert_line "expired R5 also rejects cached seven_day" 2 '7d --'
assert_line "expired R5 keeps session cost" 2 '\$1\.23'
printf '30|15|%s|%s\n' "$((NOW + 12000))" "$NOW" >"$QC"
OUTPUT=$(run_with_env "$EXPIRED_HOME" "$EXPIRED_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}')
assert_line "expired R7 also rejects cached five_hour" 2 '5h --'
assert_line "expired R7 rejects whole snapshot" 2 '7d --'
assert_line "expired R7 keeps session cost" 2 '\$1\.23'

# ── Test 28: Empty stdin stays Claude ──
echo "Test 28: empty stdin still returns Claude"
OUTPUT=$(printf '' | bash claude-pace.sh 2>/dev/null | strip_ansi)
assert_line_count "empty stdin stays single line" 1
assert_line "empty stdin prints Claude" 1 '^Claude$'

# ── Test 29: No safe cache root skips quota cache writes ──
echo "Test 29: no safe cache root skips quota cache"
OUTPUT=$(run_without_safe_cache_root "$(
  cat <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":$((NOW + 12000))},"seven_day":{"used_percentage":15,"resets_at":$((NOW + 500000))}}}
JSON
)" | strip_ansi)
OUTPUT=$(run_without_safe_cache_root "$(
  cat <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}
JSON
)" | strip_ansi)
assert_line "no safe cache root keeps 5h --" 2 '5h --'
assert_line "no safe cache root keeps session cost" 2 '\$1\.23'

# ── Test 30: Explicit null rate_limits reuses cached quota ──
echo "Test 30: explicit null rate_limits reuses cache"
NULL_HOME="$TEST_TMP/null-home"
NULL_RUNTIME="$TEST_TMP/null-runtime"
mkdir -p "$NULL_HOME" "$NULL_RUNTIME"
run_side_effect_with_env "$NULL_HOME" "$NULL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
OUTPUT=$(run_with_env "$NULL_HOME" "$NULL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23},"rate_limits":null}')
assert_line "null rate_limits reuses cached 5h quota" 2 '5h 30%'
assert_line "null rate_limits reuses cached 7d quota" 2 '7d 15%'
assert_line_not "null rate_limits suppresses session cost" 2 '\$1\.23'

# ── Test 31: Empty-object rate_limits behaves like partial live data ──
echo "Test 31: empty-object rate_limits uses live partial behavior"
OUTPUT=$(run_with_env "$NULL_HOME" "$NULL_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23},"rate_limits":{}}')
assert_line "empty-object rate_limits shows 5h --" 2 '5h --'
assert_line "empty-object rate_limits shows 7d --" 2 '7d --'
assert_line_not "empty-object rate_limits suppresses session cost" 2 '\$1\.23'

# ── Test 32: Live quota rewrite normalizes symlink cache file ──
echo "Test 32: live quota rewrite replaces symlink quota cache"
SYMLINK_QUOTA_HOME="$TEST_TMP/symlink-quota-home"
SYMLINK_QUOTA_RUNTIME="$TEST_TMP/symlink-quota-runtime"
SYMLINK_QUOTA_ROOT="$SYMLINK_QUOTA_RUNTIME/claude-pace"
mkdir -p "$SYMLINK_QUOTA_HOME" "$SYMLINK_QUOTA_RUNTIME" "$SYMLINK_QUOTA_ROOT"
printf '30|15|9999999999|9999999999\n' >"$TEST_TMP/real-quota-cache"
ln -s "$TEST_TMP/real-quota-cache" "$(quota_cache_path_for_root "$SYMLINK_QUOTA_ROOT")"
run_side_effect_with_env "$SYMLINK_QUOTA_HOME" "$SYMLINK_QUOTA_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":9999999999},"seven_day":{"used_percentage":15,"resets_at":9999999999}}}'
if [[ -L "$(quota_cache_path_for_root "$SYMLINK_QUOTA_ROOT")" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: live quota rewrite replaces symlink quota cache"
else
  PASS=$((PASS + 1))
  echo "  PASS: live quota rewrite replaces symlink quota cache"
fi

# ── Test 33: Unreadable quota cache does not leak stderr on live path ──
echo "Test 33: unreadable quota cache stays silent on live path"
UNREADABLE_QUOTA_HOME="$TEST_TMP/unreadable-quota-home"
UNREADABLE_QUOTA_RUNTIME="$TEST_TMP/unreadable-quota-runtime"
UNREADABLE_QUOTA_ROOT="$UNREADABLE_QUOTA_RUNTIME/claude-pace"
UNREADABLE_QUOTA_ERR="$TEST_TMP/unreadable-quota.err"
mkdir -p "$UNREADABLE_QUOTA_HOME" "$UNREADABLE_QUOTA_RUNTIME" "$UNREADABLE_QUOTA_ROOT"
printf '30|15|9999999999|9999999999\n' >"$(quota_cache_path_for_root "$UNREADABLE_QUOTA_ROOT")"
chmod 000 "$(quota_cache_path_for_root "$UNREADABLE_QUOTA_ROOT")"
env HOME="$UNREADABLE_QUOTA_HOME" XDG_RUNTIME_DIR="$UNREADABLE_QUOTA_RUNTIME" USER=tester PATH="$PATH" \
  bash claude-pace.sh >/dev/null 2>"$UNREADABLE_QUOTA_ERR" <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":9999999999},"seven_day":{"used_percentage":15,"resets_at":9999999999}}}
JSON
chmod 600 "$(quota_cache_path_for_root "$UNREADABLE_QUOTA_ROOT")"
if [[ ! -s "$UNREADABLE_QUOTA_ERR" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: unreadable quota cache stays silent on live path"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: unreadable quota cache stays silent on live path"
  echo "    stderr:"
  sed 's/^/    /' "$UNREADABLE_QUOTA_ERR"
fi

# ── Test 34: Effort level words for all five levels ──
echo "Test 34: effort level words"
EFFORT_HOME="$TEST_TMP/effort-home"
EFFORT_RUNTIME="$TEST_TMP/effort-runtime"
mkdir -p "$EFFORT_HOME/.claude" "$EFFORT_RUNTIME"
effort_input() {
  printf '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":%d},"seven_day":{"used_percentage":15,"resets_at":%d}}}' \
    "$PWD" "$((NOW + 12000))" "$((NOW + 500000))"
}
for level in low medium high xhigh max; do
  printf '{"effortLevel":"%s"}\n' "$level" >"$EFFORT_HOME/.claude/settings.json"
  OUTPUT=$(run_with_env "$EFFORT_HOME" "$EFFORT_RUNTIME" "$(effort_input)")
  assert_line "effort $level shows word" 1 " $level "
  assert_aligned "| aligned for effort $level"
done
rm -f "$EFFORT_HOME/.claude/settings.json"
OUTPUT=$(run_with_env "$EFFORT_HOME" "$EFFORT_RUNTIME" "$(effort_input)")
assert_line "absent settings.json falls back to medium word" 1 ' medium '

# ── Test 35: Effort level from stdin (CC ≥ 2.1.119) ──
echo "Test 35: effort level from stdin"
STDIN_EFFORT_HOME="$TEST_TMP/stdin-effort-home"
STDIN_EFFORT_RUNTIME="$TEST_TMP/stdin-effort-runtime"
mkdir -p "$STDIN_EFFORT_HOME/.claude" "$STDIN_EFFORT_RUNTIME"
effort_stdin_input() {
  local level="$1"
  printf '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":20,"context_window_size":200000},"effort":{"level":"%s"},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":%d},"seven_day":{"used_percentage":15,"resets_at":%d}}}' \
    "$PWD" "$level" "$((NOW + 12000))" "$((NOW + 500000))"
}
for level in low medium high xhigh max; do
  OUTPUT=$(run_with_env "$STDIN_EFFORT_HOME" "$STDIN_EFFORT_RUNTIME" "$(effort_stdin_input "$level")")
  assert_line "stdin effort $level shows word" 1 " $level "
  assert_aligned "| aligned for stdin effort $level"
done

# ── Test 36: Stdin effort.level overrides settings.json effortLevel ──
echo "Test 36: stdin effort overrides settings.json"
printf '{"effortLevel":"low"}\n' >"$STDIN_EFFORT_HOME/.claude/settings.json"
OUTPUT=$(run_with_env "$STDIN_EFFORT_HOME" "$STDIN_EFFORT_RUNTIME" "$(effort_stdin_input "max")")
assert_line "stdin effort.level wins over settings.json" 1 ' max '
assert_aligned "| aligned with stdin override"
rm -f "$STDIN_EFFORT_HOME/.claude/settings.json"

# ── Test 37: Truncation budget (28) fits longest word without ellipsis ──
# "Sonnet 4.6 (200K) medium" = 24 chars; budget=28 keeps it whole, budget=22 would clip to "Sonnet 4.6 (20… medium".
echo "Test 37: truncation budget fits longest word"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"effort":{"level":"medium"},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$((NOW + 12000))'},"seven_day":{"used_percentage":15,"resets_at":'$((NOW + 500000))'}}}')
assert_line "Sonnet 4.6 (200K) medium fits without ellipsis" 1 'Sonnet 4\.6 \(200K\) medium'
assert_line_not "no ellipsis on medium with mid-length model" 1 '…'

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
