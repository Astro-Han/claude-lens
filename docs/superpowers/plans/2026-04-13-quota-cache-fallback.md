# Quota Cache Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a last-known stdin quota cache so `claude-pace` can reuse the previous 5h/7d snapshot when a later run has `HAS_RL=0`, while preserving current empty-stdin behavior and session-cost fallback semantics.

**Architecture:** Keep the feature local to `claude-pace.sh` and `test.sh`. Reuse the existing private cache root and record helpers, add one quota cache file (`claude-sl-quota`), write only fully valid live snapshots, and read only when `HAS_RL=0`. Reject invalid or expired cached reset epochs, never backfill partial live payloads from cache, and keep session cost suppressed only on cache hit.

**Tech Stack:** Bash, jq, existing shell test harness in `test.sh`

**Spec:** `docs/superpowers/specs/2026-04-13-quota-cache-fallback-design.md`

---

## File Structure

- `claude-pace.sh`
  Purpose: add one quota-cache path, one validation helper, one write path in the live branch, and one read path in the `HAS_RL=0` branch. Do not restructure the rest of the script.
- `test.sh`
  Purpose: add quota-cache regression coverage for cache hit, invalid cache, partial live payloads, expired reset epochs, empty stdin, and no-safe-cache-root behavior.
- `README.md`
  Purpose: document the new fallback behavior and remove stale wording that still implies the old Usage API fallback exists.
- `CHANGELOG.md`
  Purpose: record the user-visible behavior change in an `Unreleased` section.

---

### Task 1: Core Quota Cache Fallback

**Files:**
- Modify: `test.sh`
- Modify: `claude-pace.sh`

- [ ] **Step 1: Add test helpers and two failing quota-cache tests**

In `test.sh`, add two helpers after `assert_line()`:

```bash
assert_line_not() {
  local name="$1" line_num="$2" pattern="$3" actual
  actual=$(echo "$OUTPUT" | sed -n "${line_num}p")
  if [[ ! "$actual" =~ $pattern ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    unexpected pattern: $pattern"
    echo "    actual:             $actual"
  fi
}

quota_cache_path_for_root() {
  local cache_root="$1"
  printf '%s/claude-sl-quota\n' "$cache_root"
}
```

Then add these tests after current Test 18 and before `# ── Summary ──`:

```bash
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
```

- [ ] **Step 2: Run the regression suite to verify the new tests fail**

Run:

```bash
bash test.sh
```

Expected:

```text
FAIL: quota cache file created from live rate_limits
FAIL: cached 5h quota shown
FAIL: cached 7d quota shown
FAIL: cached quota suppresses session cost
```

- [ ] **Step 3: Implement the quota-cache path, validation helper, and read/write logic**

In `claude-pace.sh`, add this helper after `_minutes_until()`:

```bash
_valid_quota_snapshot() {
  local u5="$1" u7="$2" r5="$3" r7="$4"
  [[ "$u5" =~ ^[0-9]+$ ]] || return 1
  [[ "$u7" =~ ^[0-9]+$ ]] || return 1
  [[ "$r5" =~ ^[0-9]+$ ]] || return 1
  [[ "$r7" =~ ^[0-9]+$ ]] || return 1
  ((r5 > NOW && r7 > NOW))
}
```

Then add one quota-cache path after the cache-root selection block:

```bash
QC=""
[[ "$CACHE_OK" == "1" ]] && QC="${_CD}/claude-sl-quota"
```

Then replace the current usage-data block with:

```bash
# Usage data: read stdin rate_limits when available, otherwise show session cost.
SHOW_COST=0
if [[ "$HAS_RL" == "1" ]]; then
  # Stdin path: real-time, no network. U5/U7 already set by jq read above.
  # Guard: resets_at=0 means field missing, leave RM empty so _usage skips it.
  RM5=$(_minutes_until "$R5")
  RM7=$(_minutes_until "$R7")
  if [[ -n "$QC" ]] && _valid_quota_snapshot "$U5" "$U7" "$R5" "$R7"; then
    _write_cache_record "$QC" "$U5" "$U7" "$R5" "$R7" || true
  fi
else
  U5="--" U7="--" RM5="" RM7=""
  SHOW_COST=1
  if [[ -n "$QC" ]] && _load_cache_record_file "$QC"; then
    _CU5=${CACHE_FIELDS[0]:-}
    _CU7=${CACHE_FIELDS[1]:-}
    _CR5=${CACHE_FIELDS[2]:-}
    _CR7=${CACHE_FIELDS[3]:-}
    if _valid_quota_snapshot "$_CU5" "$_CU7" "$_CR5" "$_CR7"; then
      U5="$_CU5"
      U7="$_CU7"
      R5="$_CR5"
      R7="$_CR7"
      RM5=$(_minutes_until "$R5")
      RM7=$(_minutes_until "$R7")
      SHOW_COST=0
    fi
  fi
fi
```

- [ ] **Step 4: Run the full regression suite to verify the core behavior passes**

Run:

```bash
bash test.sh
```

Expected:

```text
PASS: quota cache file created from live rate_limits
PASS: cached 5h quota shown
PASS: cached 7d quota shown
PASS: cached quota suppresses session cost
Results: ... 0 failed
```

- [ ] **Step 5: Commit the core fallback**

```bash
git add claude-pace.sh test.sh
git commit -m "feat: add quota cache fallback"
```

---

### Task 2: Edge-Case Regression Coverage

**Files:**
- Modify: `test.sh`

- [ ] **Step 1: Add invalid-cache, partial-live, expired-reset, and empty-stdin tests**

Append these tests after Task 1’s new tests and before `# ── Summary ──`:

```bash
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
OUTPUT=$(env HOME="/dev/null" XDG_RUNTIME_DIR="" USER=tester PATH="$PATH" \
  bash claude-pace.sh 2>/dev/null <<<"$(
    cat <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":$((NOW + 12000))},"seven_day":{"used_percentage":15,"resets_at":$((NOW + 500000))}}}
JSON
  )" | strip_ansi)
OUTPUT=$(env HOME="/dev/null" XDG_RUNTIME_DIR="" USER=tester PATH="$PATH" \
  bash claude-pace.sh 2>/dev/null <<<"$(
    cat <<JSON
{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"$PWD"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}
JSON
  )" | strip_ansi)
assert_line "no safe cache root keeps 5h --" 2 '5h --'
assert_line "no safe cache root keeps session cost" 2 '\$1\.23'
```

- [ ] **Step 2: Run the regression suite again**

Run:

```bash
bash test.sh
```

Expected:

```text
PASS: invalid cache falls back to no quota 5h
PASS: partial live missing five_hour renders 5h --
PASS: cache keeps original seven_day after missing five_hour partial live
PASS: expired live R5 keeps cached five_hour
PASS: cache survives missing seven_day partial live
PASS: expired R5 rejects whole snapshot
PASS: empty stdin prints Claude
Results: ... 0 failed
```

- [ ] **Step 3: Commit the regression coverage**

```bash
git add test.sh
git commit -m "test: cover quota cache edge cases"
```

---

### Task 3: Documentation Sync and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Test: `test.sh`

- [ ] **Step 1: Update README source table and FAQ**

In `README.md`, replace the quota source row with:

```markdown
| Quota (5h, 7d, pace) | stdin `rate_limits`; fallback to last-known private cache when `rate_limits` is absent | Private cache root, accepted only before cached reset |
```

Then replace the current “Does it make network calls?” answer with:

```markdown
**Does it make network calls?**
No. Quota data comes from stdin `rate_limits` on Claude Code `2.1.80+`. If a later statusline run omits `rate_limits`, claude-pace can reuse the last known stdin quota snapshot from its private cache as long as that snapshot's reset times are still in the future. Otherwise it falls back to `--` and may still show the local session cost.
```

Also replace the earlier README sentence that still mentions the old Usage API fallback with:

```markdown
Best experience is on Claude Code `2.1.80+`, where `rate_limits` is available in statusline stdin. When a later statusline run omits `rate_limits`, claude-pace can reuse the last known stdin quota snapshot from its private cache until either cached reset time expires.
```

- [ ] **Step 2: Add an `Unreleased` changelog entry**

At the top of `CHANGELOG.md`, insert:

```markdown
## Unreleased

- Reuse the last known stdin quota snapshot when `rate_limits` is absent, as long as both cached reset times are still in the future
- Ignore invalid, expired, or partial-live quota snapshots instead of overwriting a previously good cache
```

- [ ] **Step 3: Run the full regression suite**

Run:

```bash
bash test.sh
```

Expected:

```text
Results: ... 0 failed
```

- [ ] **Step 4: Smoke-test the new fallback manually**

Run:

```bash
SMOKE_HOME=$(mktemp -d)
SMOKE_RUNTIME=$(mktemp -d)
LIVE_INPUT='{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'$PWD'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$(($(date +%s)+12000))'},"seven_day":{"used_percentage":15,"resets_at":'$(($(date +%s)+500000))'}}}'
MISS_INPUT='{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'$PWD'"},"context_window":{"used_percentage":20,"context_window_size":200000},"cost":{"total_cost_usd":1.23}}'
printf '%s\n' "$LIVE_INPUT" | env HOME="$SMOKE_HOME" XDG_RUNTIME_DIR="$SMOKE_RUNTIME" USER=tester PATH="$PATH" bash claude-pace.sh
printf '%s\n' "$MISS_INPUT" | env HOME="$SMOKE_HOME" XDG_RUNTIME_DIR="$SMOKE_RUNTIME" USER=tester PATH="$PATH" bash claude-pace.sh
rm -rf "$SMOKE_HOME" "$SMOKE_RUNTIME"
```

Expected:

```text
The second run shows `5h 30%` and `7d 15%`, with no `$1.23` suffix.
```

- [ ] **Step 5: Commit the docs and final verification milestone**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: describe quota cache fallback"
```

---

## Self-Review

### Spec Coverage

- Summary / Goals: covered by Task 1 implementation and Task 3 docs.
- No network / no API / no TTL / no backfill: enforced in Task 1 implementation snippet and Task 2 partial-live tests.
- `HAS_RL=1` write only from fully valid snapshot: covered in Task 1 implementation and Task 2 partial-live tests.
- `HAS_RL=0` cache hit suppresses cost: covered in Task 1 tests and implementation.
- Invalid or expired cached resets degrade to no-quota fallback: covered in Task 2 tests and Task 1 helper.
- Expired live snapshots do not overwrite a previously good cache: covered in Task 2 test 26.
- Empty stdin unchanged: covered in Task 2 test 28.
- No safe cache root behavior: covered in Task 2 test 29.
- Docs sync for changed behavior: covered in Task 3.

### Placeholder Scan

- No `TODO`, `TBD`, or deferred implementation notes remain.
- Every code-changing step includes an explicit code block.
- Every verification step includes an exact command and expected outcome.

### Type Consistency

- Cache record order is consistently `U5`, `U7`, `R5`, `R7`.
- Validation helper and tests consistently treat `U5/U7` as non-negative integers and `R5/R7` as epoch integers.
- `SHOW_COST` behavior is consistent across plan, spec, and test expectations.
