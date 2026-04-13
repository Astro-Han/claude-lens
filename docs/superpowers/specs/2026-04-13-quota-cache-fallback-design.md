# Quota Cache Fallback Design

Date: 2026-04-13
Project: `claude-pace`
Scope: missing-`rate_limits` fallback only

## Summary

Add a small last-known quota cache for the case where Claude Code provides normal statusline JSON but `rate_limits` is absent or null (i.e. whenever the existing parse logic yields `HAS_RL=0`).

The cache stores the last successful stdin quota values:

- `U5`
- `U7`
- `R5`
- `R7`

When live quota data is present, the script renders it as it does today and refreshes the cache only from a fully valid snapshot. When `rate_limits` is absent, the script reads the cached quota and renders it exactly like live quota only when the cached reset epochs are still in the future. If the cache is missing, invalid, or already past reset, the script keeps the current no-quota fallback behavior, including session cost when available.

Empty stdin remains unchanged and continues to render `Claude`.

## Goals

- Preserve the current lightweight, stdin-first architecture
- Improve continuity when `rate_limits` is temporarily absent
- Avoid reintroducing the old Usage API fallback machinery
- Reuse the existing safe private-cache model already used for git data

## Non-Goals

- No network fallback
- No transcript or JSONL parsing
- No stale marker or alternate display state
- No wall-clock TTL or file-age freshness policy (validity is determined solely by the cached reset epochs)
- No per-project quota cache
- No change to the empty-stdin behavior

## User-Facing Behavior

### Case 1: Live quota present

When `HAS_RL=1`:

- Render quota exactly as today
- Compute countdowns from live `resets_at`
- Overwrite the last-known quota cache with `U5/U7/R5/R7` only if all four fields validate for cache storage
- If live `rate_limits` is partial or malformed (i.e. `HAS_RL=1` but one or more of `five_hour.used_percentage`, `five_hour.resets_at`, `seven_day.used_percentage`, `seven_day.resets_at` is missing or non-numeric), rendering follows existing behavior unchanged: missing `used_percentage` renders `--`, missing `resets_at` suppresses countdown and pace for that window. Session cost remains suppressed because `HAS_RL=1`
- Do not backfill missing live fields from cache
- Do not overwrite a previously good cache from a partial or malformed live snapshot (this write-guard is the only new logic in the partial case; rendering is already handled)

### Case 2: `rate_limits` absent

When `HAS_RL=0`:

- Attempt to read the last-known quota cache
- If the cache is valid and both cached `R5` and `R7` are still in the future, render it exactly like live quota and suppress session cost
- If the cache is missing, unreadable, invalid, or already past reset, keep the current no-quota fallback, including session cost when available

Cached quota is intentionally rendered without any stale marker. This is a deliberate simplicity tradeoff.

### Case 3: Empty stdin

If stdin is empty:

- Keep the current early exit
- Keep rendering `Claude`
- Do not try to use cached quota

This preserves the current troubleshooting signal for a fully broken statusline invocation.

## Internal Design

### Cache location

Store the quota cache in the same verified private cache root already used for git:

- `$XDG_RUNTIME_DIR/claude-pace`
- fallback: `~/.cache/claude-pace`

If no safe cache root is available, caching remains disabled for that run.

### Cache shape

Use one global quota cache file `claude-sl-quota` in the cache root, not a per-project key.

Reason:

- 5h and 7d quota are account-level data
- Keying by project would make the fallback weaker without adding correctness

The cache record stores the already-normalized shell values (post-jq-floor integers for U5/U7, integer epoch for R5/R7), not raw JSON floats. Record format: `U5<SEP>U7<SEP>R5<SEP>R7` (4 fields in this order, same separator as git cache; read via `CACHE_FIELDS[0..3]`):

- `CACHE_FIELDS[0]` = `U5`
- `CACHE_FIELDS[1]` = `U7`
- `CACHE_FIELDS[2]` = `R5`
- `CACHE_FIELDS[3]` = `R7`

Use the existing cache helpers:

- `_write_cache_record`
- `_load_cache_record_file`
- compatibility reader behavior already built into cache parsing

No new cache abstraction should be introduced.

### Read/write rules

- Write quota cache only when `HAS_RL=1` and all four cache fields validate
- Read quota cache only when `HAS_RL=0`
- If cache write fails, ignore the failure and keep rendering live data
- If cache read fails, fields are invalid, or cached reset epochs are expired, fall back to `--`
- On cache hit, suppress session cost so cached quota renders the same way as live quota
- On cache miss or invalid cache, preserve the current session-cost behavior

## Validation and Failure Handling

The cache must be treated as untrusted persisted input.

After reading the quota cache:

- `U5` and `U7` must be non-negative integers (matching the existing `^[0-9]+$` live-path check; values above 100 are valid during overuse)
- `R5` and `R7` must be validated as numeric epoch values before converting to remaining minutes
- cached `R5` and `R7` must still be greater than `NOW`
- If either cached reset epoch is already expired, treat the entire cache snapshot as invalid for fallback rendering

Before writing the quota cache:

- `U5` and `U7` must be non-negative integers (matching the live-path regex)
- `R5` and `R7` must be numeric epoch values greater than `NOW`
- If any field is invalid or any reset epoch is already expired, skip the cache write and preserve the existing cache contents

If any required field is invalid:

- Ignore the cache
- Fall back to `U5="--" U7="--" RM5="" RM7=""` (SHOW_COST remains unchanged from the HAS_RL=0 default)

Do not add repair logic, migration logic, partial-cache recovery logic, or cache backfill beyond the existing compatibility reader.

## Implementation Boundaries

The change should remain local to the current usage block and cache setup:

- define one quota-cache path near the existing cache-root setup
- update the `HAS_RL=1` path to persist `U5/U7/R5/R7`
- update the `HAS_RL=0` path to try cached quota before falling back to `--`

Do not:

- reintroduce API polling
- add background refresh
- add lock files
- add timestamps or TTL decisions
- change line layout or formatting

## Testing

Add tests for the following:

1. Live quota present, followed by missing `rate_limits`:
   the second run renders the previously cached quota values and does not show session cost.
2. Missing `rate_limits` with no quota cache:
   output remains the current no-quota fallback, including session cost when available.
3. Invalid quota cache contents:
   the script ignores the cache and degrades to the current no-quota fallback.
4. Seed a good quota cache, then provide partial live `rate_limits` in three shapes:
   (a) `rate_limits` present but `five_hour` absent entirely,
   (b) `rate_limits.five_hour.used_percentage` present but `resets_at` missing,
   (c) `rate_limits` present but `seven_day` absent entirely.
   In all cases the good cache must not be overwritten, and session cost must stay suppressed.
5. Seed a good quota cache, then provide a later missing-`rate_limits` run:
   the script still uses the older valid cache.
6. Cached reset epochs at or before `NOW` (two sub-cases):
   (a) seed R5 with `$(date +%s)` (equal to or 1s before script's NOW) and R7 still in the future,
   (b) seed R7 with `$(date +%s)` and R5 still in the future.
   Both must reject the entire snapshot. This tests the "either expired invalidates all" rule at the exact boundary from both sides.
7. Empty stdin:
   output remains `Claude`, not cached quota.
8. No safe cache root:
   quota cache read/write is skipped and behavior degrades cleanly.

## Tradeoff

This design accepts three intentional tradeoffs:

- cached quota may be stale if the same account is used elsewhere, or if different accounts share the same machine (there is no account key in stdin to differentiate; the global cache reflects whichever account wrote last)
- cached U5/U7 are frozen while time advances, so the pace delta will drift toward "under budget" as the current moment approaches the cached reset epoch; this is bounded by the reset-epoch expiry check and is negligible during a brief absence gap
- cached quota is still only accepted before its own reset boundary; once the cached reset time has passed, the snapshot is discarded instead of rendered

These tradeoffs are acceptable because the goal is continuity with minimal complexity, not a global source of truth.

## Acceptance Criteria

- No new dependency is introduced
- No network call is introduced
- No new user-facing mode or marker is introduced
- Missing `rate_limits` can render the last known quota from stdin
- Empty stdin behavior remains unchanged
- Partial or malformed live `rate_limits` cannot poison a previously good cache
- Partial live `rate_limits` render only their present live fields, do not backfill from cache, and suppress session cost
- Cache-hit rendering suppresses session cost; cache-miss rendering preserves current session-cost fallback behavior
- Cached reset epochs at or before `NOW` are treated as invalid for fallback rendering
- Invalid cache data cannot break rendering or arithmetic paths
