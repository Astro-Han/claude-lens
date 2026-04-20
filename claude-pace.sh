#!/usr/bin/env bash
# Claude Code statusline plugin
# Line1: model (ctx) effort | project (branch) Nf +A -D
# Line2: bar PCT% CL | 5h used% [⇡⇣pace] countdown  7d used% [⇡⇣pace] countdown

# Disable glob expansion so unquoted vars with wildcards (e.g. DIR paths)
# are never accidentally expanded into filename lists.
set -f
input=$(cat)
[ -z "$input" ] && {
  echo "Claude"
  exit 0
}
command -v jq >/dev/null || {
  echo "Claude [needs jq]"
  exit 0
}

# ── Colors & Utilities ──
# C=Cyan G=Green Y=Yellow R=Red D=Dim N=Normal (reset)
# Store real escape bytes so final output does not need echo -e interpretation.
C=$'\033[36m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m'
# Cache records use ASCII Unit Separator so legal Git ref names cannot split
# serialized fields and empty values survive round-trips through read.
SEP=$'\037'
NOW=$(date +%s)
# Returns true when the candidate cache dir is a real directory owned by the
# current user, writable, and not a symlink into a foreign-controlled path.
_cache_dir_ok() { [ -d "$1" ] && [ ! -L "$1" ] && [ -O "$1" ] && [ -w "$1" ]; }
# Reads one cache record into CACHE_FIELDS, supporting the current separator
# and the legacy pipe format used by older cache files.
_read_cache_record() {
  local line="$1" delim rest field
  CACHE_FIELDS=()
  if [[ "$line" == *"$SEP"* ]]; then
    delim="$SEP"
  else
    delim='|'
  fi
  rest="$line"
  while [[ "$rest" == *"$delim"* ]]; do
    field=${rest%%"$delim"*}
    CACHE_FIELDS+=("$field")
    rest=${rest#*"$delim"}
  done
  CACHE_FIELDS+=("$rest")
}
# Loads and parses one cache file into CACHE_FIELDS.
_load_cache_record_file() {
  local path="$1" line=""
  [ -f "$path" ] || return 1
  IFS= read -r line <"$path" || line=""
  _read_cache_record "$line"
}
# Writes one cache record atomically. If mktemp fails, the caller skips the
# cache update and keeps serving live data for this run.
_write_cache_record() {
  local path="$1" tmp dir
  shift
  dir=${path%/*}
  tmp=$(mktemp "${dir}/claude-sl-tmp-XXXXXX" 2>/dev/null || true)
  [ -n "$tmp" ] || return 1
  (
    IFS="$SEP"
    printf '%s\n' "$*"
  ) >"$tmp" && mv "$tmp" "$path"
}
# Avoids rewriting the quota cache when the live snapshot is unchanged.
_write_quota_snapshot_if_changed() {
  local path="$1" u5="$2" u7="$3" r5="$4" r7="$5"
  if [ -f "$path" ] && [ ! -L "$path" ] && [ -r "$path" ] && _load_cache_record_file "$path"; then
    [[ "${CACHE_FIELDS[0]:-}" == "$u5" ]] &&
      [[ "${CACHE_FIELDS[1]:-}" == "$u7" ]] &&
      [[ "${CACHE_FIELDS[2]:-}" == "$r5" ]] &&
      [[ "${CACHE_FIELDS[3]:-}" == "$r7" ]] && return 0
  fi
  _write_cache_record "$path" "$u5" "$u7" "$r5" "$r7"
}
# Computes remaining whole minutes until a future epoch. Missing or expired
# timestamps return an empty string so callers can skip countdown formatting.
_minutes_until() {
  local epoch="$1" mins
  [[ "$epoch" =~ ^[0-9]+$ ]] && ((epoch > 0)) || return
  mins=$(((epoch - NOW) / 60))
  ((mins < 0)) && mins=0
  printf '%s\n' "$mins"
}
# Valid quota snapshots must contain integer usage values and future reset
# epochs for both windows. Partial or expired snapshots never enter the cache.
_valid_quota_snapshot() {
  local u5="$1" u7="$2" r5="$3" r7="$4"
  [[ "$u5" =~ ^[0-9]+$ ]] || return 1
  [[ "$u7" =~ ^[0-9]+$ ]] || return 1
  [[ "$r5" =~ ^[0-9]+$ ]] || return 1
  [[ "$r7" =~ ^[0-9]+$ ]] || return 1
  ((r5 > NOW && r7 > NOW))
}
# Collects live Git metadata for DIR. On non-repos, leaves defaults in place
# and returns non-zero so callers can decide whether to cache the empty result.
_collect_git_info() {
  BR="" FC=0 AD=0 DL=0
  git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  BR=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
  while IFS=$'\t' read -r a d _; do
    # Skip binary files (reported as "-" instead of a number).
    [[ "$a" =~ ^[0-9]+$ ]] || continue
    FC=$((FC + 1))
    AD=$((AD + a))
    DL=$((DL + d))
  done < <(git -C "$DIR" --no-optional-locks diff HEAD --numstat 2>/dev/null)
}
# Cache only inside a user-owned, non-symlinked directory. If no safe root is
# available, disable caching for this run instead of falling back to shared /tmp.
_CD="" CACHE_OK=0
for _BASE in "${XDG_RUNTIME_DIR:-}" "${HOME}/.cache"; do
  [ -n "$_BASE" ] || continue
  _CAND="${_BASE%/}/claude-pace"
  # shellcheck disable=SC2174  # -p only creates leaf here; parent already exists
  [ -e "$_CAND" ] || mkdir -p -m 700 "$_CAND" 2>/dev/null || continue
  _cache_dir_ok "$_CAND" || continue
  _CD="$_CAND"
  CACHE_OK=1
  break
done
QC=""
[[ "$CACHE_OK" == "1" ]] && QC="${_CD}/claude-sl-quota"
# Returns true (exit 0) when file is missing or older than $2 seconds.
_stale() { [ ! -f "$1" ] || [ $((NOW - $(stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0))) -gt "$2" ]; }

# ── Parse stdin + settings in one jq call ──
# Fields: MODEL DIR PCT CTX COST EFF HAS_RL U5 U7 R5 R7
HAS_RL=0
IFS=$'\t' read -r MODEL DIR PCT CTX COST EFF HAS_RL U5 U7 R5 R7 < <(
  jq -r --slurpfile cfg <(cat ~/.claude/settings.json 2>/dev/null || echo '{}') \
    '[(.model.display_name//"?"),(.workspace.project_dir//"."),
    (.context_window.used_percentage//0|floor),(.context_window.context_window_size//0),
    (.cost.total_cost_usd//0),
    ($cfg[0].effortLevel//"default"),
    (if .rate_limits then 1 else 0 end),
    (.rate_limits.five_hour.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.seven_day.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.five_hour.resets_at//0),
    (.rate_limits.seven_day.resets_at//0)]|@tsv' <<<"$input"
)
case "${EFF:-default}" in low) EF='◌' ;; high) EF='◎' ;; xhigh) EF='◉' ;; max) EF='●' ;; *) EF='○' ;; esac

# ── Context label (needed by MODEL_SHORT and line 2) ──
if ((CTX >= 1000000)); then
  CL="$((CTX / 1000000))M"
elif ((CTX > 0)); then
  CL="$((CTX / 1000))K"
else CL=""; fi

# ── MODEL_SHORT: strip redundant context label ──
MODEL=${MODEL/ context)/)}
[[ "$CTX" -gt 0 && "$MODEL" != *"("* ]] && MODEL="${MODEL} (${CL})"
# Truncate long model names to keep padding within 0-5 chars.
_ML="${MODEL} ${EF}"
((${#_ML} > 22)) && MODEL="${MODEL:0:$((22 - 2 - ${#EF}))}…"

# ── Progress Bar ──
F=$((PCT / 10))
((F < 0)) && F=0
((F > 10)) && F=10
if ((PCT >= 90)); then BC=$R; elif ((PCT >= 70)); then BC=$Y; else BC=$G; fi
BAR=""
for ((i = 0; i < F; i++)); do BAR+='█'; done
for ((i = F; i < 10; i++)); do BAR+='░'; done

# ── Git Info (5s cache, atomic write) ──
# Cache key encodes DIR so concurrent sessions in different repos don't clash.
# Atomic write: write to a temp file first, then mv to avoid partial reads.
BR="" FC=0 AD=0 DL=0
if [[ "$CACHE_OK" == "1" ]]; then
  GC="${_CD}/claude-sl-git-$(printf '%s' "$DIR" | { shasum 2>/dev/null || sha1sum; } | cut -c1-16)"
  if _stale "$GC" 5; then
    if _collect_git_info; then
      _write_cache_record "$GC" "$BR" "$FC" "$AD" "$DL"
    else
      _write_cache_record "$GC" "" "" "" ""
    fi
  elif _load_cache_record_file "$GC"; then
    BR=${CACHE_FIELDS[0]:-}
    FC=${CACHE_FIELDS[1]:-}
    AD=${CACHE_FIELDS[2]:-}
    DL=${CACHE_FIELDS[3]:-}
  fi
  # Reject cache corruption before arithmetic or terminal output formatting.
  [[ "$FC" =~ ^[0-9]+$ ]] || FC=0
  [[ "$AD" =~ ^[0-9]+$ ]] || AD=0
  [[ "$DL" =~ ^[0-9]+$ ]] || DL=0
else
  _collect_git_info || true
fi

# ── Project Name + Line 1 Right Section ──
# Extract project name. Worktree: save repo name explicitly.
PN="${DIR##*/}"
IS_WT=0 _REPO=""
if [[ "${DIR/#$HOME/\~}" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
  IS_WT=1
  _REPO="${BASH_REMATCH[1]}"
  _WT_NAME="${BASH_REMATCH[2]}"
  PN="$_REPO"
fi
((${#PN} > 25)) && PN="${PN:0:25}…"

# Format: project (branch) [git stats]
L1R="$PN"
if [ -n "$BR" ]; then
  ((${#BR} > 35)) && BR="${BR:0:35}…"
  L1R+=" (${BR})"
  ((FC > 0)) 2>/dev/null && L1R+=" ${FC}f ${G}+${AD}${N} ${R}-${DL}${N}"
elif [[ "$IS_WT" == "1" ]]; then
  # Detached HEAD in worktree: show repo/worktree to preserve identity
  L1R="${_REPO}/${_WT_NAME}"
  ((${#L1R} > 25)) && L1R="${L1R:0:25}…"
fi

# Usage data: read stdin rate_limits when available, otherwise show session cost.
SHOW_COST=0
if [[ "$HAS_RL" == "1" ]]; then
  # Stdin path: real-time, no network. U5/U7 already set by jq read above.
  # Guard: resets_at=0 means field missing, leave RM empty so _usage skips it.
  RM5=$(_minutes_until "$R5")
  RM7=$(_minutes_until "$R7")
  if [[ -n "$QC" ]] && _valid_quota_snapshot "$U5" "$U7" "$R5" "$R7"; then
    _write_quota_snapshot_if_changed "$QC" "$U5" "$U7" "$R5" "$R7" || true
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

# Combined usage formatter: used% [pace delta] (countdown)
_usage() {
  local u="${1:---}" rm="$2" w="$3"
  if [[ ! "$u" =~ ^[0-9]+$ ]]; then
    printf "%s" "$u"
  else
    if ((u >= 90)); then printf "${R}%d%%${N}" "$u"; elif ((u >= 70)); then printf "${Y}%d%%${N}" "$u"; else printf "${G}%d%%${N}" "$u"; fi
    if [[ "$rm" =~ ^[0-9]+$ ]] && ((rm <= w)); then
      # Pace delta: positive = over pace (overspend), negative = under pace (surplus).
      local d=$((u - (w - rm) * 100 / w))
      ((d > 0)) && printf " ${R}⇡%d%%${N}" "$d"
      ((d < 0)) && printf " ${G}⇣%d%%${N}" "${d#-}"
    fi
  fi
  [[ "$rm" =~ ^[0-9]+$ ]] || return
  ((rm >= 1440)) && {
    printf " ${D}%dd${N}" $((rm / 1440))
    return
  }
  ((rm >= 60)) && {
    printf " ${D}%dh${N}" $((rm / 60))
    return
  }
  printf " ${D}%dm${N}" "$rm"
}

# ── Output Assembly (symmetric single-pipe alignment) ──

# Build plain-text left sections for width measurement (no ANSI codes).
L1_PLAIN="${MODEL} ${EF}"
L2_PLAIN="${BAR} ${PCT}% ${CL}"
# Pad shorter side so | aligns on both lines.
W1=${#L1_PLAIN} W2=${#L2_PLAIN}
PAD1="" PAD2=""
if ((W1 > W2)); then
  printf -v PAD2 "%*s" $((W1 - W2)) ""
elif ((W2 > W1)); then
  printf -v PAD1 "%*s" $((W2 - W1)) ""
fi

# Line 1: model (context) effort | project (branch) git-stats
L1="${C}${MODEL} ${EF}${N}${PAD1} ${D}|${N}  ${L1R}"

# Line 2: bar pct% CL | 5h used% ...  7d used% ...
L2="${BC}${BAR}${N} ${PCT}% ${CL}${PAD2} ${D}|${N}  5h $(_usage "$U5" "$RM5" 300)  7d $(_usage "$U7" "$RM7" 10080)"
# Session cost: only when usage data is unavailable in stdin.
if [[ "$SHOW_COST" == "1" ]]; then
  printf -v _CS "\$%.2f" "$COST" 2>/dev/null
  [[ "$_CS" != "\$0.00" ]] && L2+="  $_CS"
fi

printf '%s\n' "$L1"
printf '%s\n' "$L2"
