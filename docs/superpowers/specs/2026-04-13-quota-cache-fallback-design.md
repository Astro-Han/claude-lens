# Quota Cache Fallback Design

Date: 2026-04-13
Project: `claude-pace`
Scope: missing-`rate_limits` fallback only

## Summary

Add a small last-known quota cache for the case where Claude Code provides normal statusline JSON but omits `rate_limits`.

The cache stores the last successful stdin quota values:

- `U5`
- `U7`
- `R5`
- `R7`

When live quota data is present, the script renders it as it does today and refreshes the cache. When `rate_limits` is absent, the script reads the cached quota and renders it exactly like live data. If the cache is missing or invalid, the script keeps the current `5h --  7d --` behavior.

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
- No TTL or freshness policy
- No per-project quota cache
- No change to the empty-stdin behavior

## User-Facing Behavior

### Case 1: Live quota present

When `HAS_RL=1`:

- Render quota exactly as today
- Compute countdowns from live `resets_at`
- Overwrite the last-known quota cache with `U5/U7/R5/R7`

### Case 2: `rate_limits` absent

When `HAS_RL=0`:

- Attempt to read the last-known quota cache
- If the cache is valid, render it exactly like live quota
- If the cache is missing, unreadable, or invalid, keep the current `5h --  7d --` output

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

Use one global quota cache file, not a per-project key.

Reason:

- 5h and 7d quota are account-level data
- Keying by project would make the fallback weaker without adding correctness

The cache record contains:

- `U5`
- `U7`
- `R5`
- `R7`

Use the existing cache helpers:

- `_write_cache_record`
- `_load_cache_record_file`
- compatibility reader behavior already built into cache parsing

No new cache abstraction should be introduced.

### Read/write rules

- Write quota cache only when `HAS_RL=1`
- Read quota cache only when `HAS_RL=0`
- If cache write fails, ignore the failure and keep rendering live data
- If cache read fails or fields are invalid, fall back to `--`

## Validation and Failure Handling

The cache must be treated as untrusted persisted input.

After reading the quota cache:

- `U5` and `U7` must be validated as numeric percentages before they enter quota formatting logic
- `R5` and `R7` must be validated as numeric epoch values before converting to remaining minutes

If any required field is invalid:

- Ignore the cache
- Fall back to `U5="--" U7="--" RM5="" RM7=""`

Do not add repair logic, migration logic, or partial-cache recovery logic beyond the existing compatibility reader.

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
   the second run renders the previously cached quota values.
2. Missing `rate_limits` with no quota cache:
   output remains `5h --  7d --`.
3. Invalid quota cache contents:
   the script ignores the cache and degrades to `--`.
4. Empty stdin:
   output remains `Claude`, not cached quota.
5. No safe cache root:
   quota cache read/write is skipped and behavior degrades cleanly.

## Tradeoff

This design accepts one intentional tradeoff:

- cached quota may be stale if the same account is used elsewhere or quota changes outside the current local Claude Code flow

That tradeoff is acceptable because the goal is continuity with minimal complexity, not a global source of truth.

## Acceptance Criteria

- No new dependency is introduced
- No network call is introduced
- No new user-facing mode or marker is introduced
- Missing `rate_limits` can render the last known quota from stdin
- Empty stdin behavior remains unchanged
- Invalid cache data cannot break rendering or arithmetic paths
