# Changelog

## 0.8.4

- Read `effort.level` from stdin when available (Claude Code 2.1.119+), falling back to `~/.claude/settings.json` `effortLevel` on older versions
- Add regression coverage for stdin effort levels and stdin-over-settings precedence (thanks @lifebugz in https://github.com/Astro-Han/claude-pace/pull/11)

## 0.8.3

- Add support for the new `xhigh` effort level and handle `max` explicitly
- Redesign effort indicator glyphs to a 5-step circle family (`◌ ○ ◎ ◉ ●`) for consistent cell width across fonts
- Extend test coverage with per-level glyph and pipe alignment assertions

## 0.8.2

- Avoid rewriting the quota cache when the live stdin snapshot is unchanged
- Keep quota cache hardening intact for symlinked or unreadable cache files while preserving atomic rewrite fallback
- Simplify test helpers and add regression coverage for symlinked and unreadable quota cache files on the live path

## 0.8.1

- Reuse the last known stdin quota snapshot when `rate_limits` is absent, as long as both cached reset times are still in the future
- Ignore invalid, expired, or partial-live quota snapshots instead of overwriting a previously good cache

## 0.8.0

- Remove the Anthropic Usage API fallback, quota tracking now reads only from stdin `rate_limits`
- Quota tracking now requires Claude Code `2.1.80+`; when `rate_limits` is absent, claude-pace shows `--` for quota and may still show session cost

## 0.7.3

- API fallback can now be disabled: set `CLAUDE_PACE_API_FALLBACK=0` to turn off usage polling for CC <2.1.80
- Fix git cache key collision: paths like `/foo-bar` and `/foo/bar` no longer share a cache file (now uses SHA-1 hash)
- Old-style git cache files (path-based names like `claude-sl-git-_Users_*`) are orphaned; safe to delete from your cache directory (`$XDG_RUNTIME_DIR/claude-pace/` or `~/.cache/claude-pace/`)

## 0.7.2

- Fix OAuth token exposure in Usage API fallback: avoid leaking bearer token in curl argv / process listings
- Reject malformed tokens containing CR/LF before invoking curl

## 0.7.1

- Harden cache handling: move from shared `/tmp` to private per-user directory (`$XDG_RUNTIME_DIR/claude-pace` or `~/.cache/claude-pace`, mode 700)
- Validate all cache-read fields before arithmetic evaluation
- Switch cache delimiter from `|` to ASCII Unit Separator (branch names with `|` no longer corrupt parsing)
- Disable caching entirely when no safe cache directory is available

## 0.7.0

- Rename project from claude-lens to claude-pace
- Add `npx claude-pace` one-step installer
- Add plugin marketplace support

## 0.6.2

- Fix `((var++))` unsafe under `set -e` (exit status 1 when variable is 0)

## 0.6.1

- Remove ±5% silent zone for pace delta (any non-zero delta now visible)

## 0.6.0

- Display usage as used% instead of remaining% (lower = better)
- Use ⇡/⇣ arrows for pace delta (⇡ = overspend, ⇣ = surplus)
- Invert pace delta sign to match intuitive convention

## 0.5.0

- Symmetric single-pipe alignment redesign (~270 lines)
- Add performance metrics to comparison table
- Remove session duration display

## 0.4.1

- Merge formatting functions (`_uf`/`_pace`/`_rc`) into single `_usage`
- Restore extra usage display when actual spending exists
- Fix 7d reset countdown always showing

## 0.4.0

- Use stdin `rate_limits` for real-time usage (no network calls on CC >= 2.1.80)
- Add plugin marketplace support for one-command install
- Fix `jq null|floor` crash on jq 1.7.1

## 0.3.1

- Show reset countdown for usage windows
- Fix cache degradation: preserve good data on API failure

## 0.3.0

- Full rewrite (962 lines to 142)
- Remaining% display, pace delta, conditional cost display
