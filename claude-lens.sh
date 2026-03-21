#!/usr/bin/env bash
# Claude Code statusline plugin
# Line1: [model effort] dir | branch Nf +A -D  |  Line2: bar PCT% | 5h remain | 7d remain | [$cost] | duration
set -f
input=$(cat)
[ -z "$input" ] && { echo "Claude"; exit 0; }
command -v jq >/dev/null || { echo "Claude [needs jq]"; exit 0; }

C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m' D='\033[2m' N='\033[0m'
_pc() { (($1>=90)) && printf "$R" || { (($1>=70)) && printf "$Y" || printf "$G"; }; }
NOW=$(date +%s)
_stale() { [ ! -f "$1" ] || [ $((NOW-$(stat -f%m "$1" 2>/dev/null||stat -c%Y "$1" 2>/dev/null||echo 0))) -gt "$2" ]; }

HAS_RL=0
IFS=$'\t' read -r MODEL DIR PCT CTX DUR COST EFF HAS_RL U5 U7 R5 R7 < <(
  jq -r --slurpfile cfg <(cat ~/.claude/settings.json 2>/dev/null || echo '{}') \
  '[(.model.display_name//"?"),(.workspace.project_dir//"."),
    (.context_window.used_percentage//0|floor),(.context_window.context_window_size//0),
    (.cost.total_duration_ms//0|floor),(.cost.total_cost_usd//0),
    ($cfg[0].effortLevel//"default"),
    (if .rate_limits then 1 else 0 end),
    (.rate_limits.five_hour.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.seven_day.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.five_hour.resets_at//0),
    (.rate_limits.seven_day.resets_at//0)]|@tsv' <<< "$input")
case "${EFF:-default}" in high) EF='●';; low) EF='◔';; *) EF='◑';; esac

F=$((PCT/10)); ((F<0)) && F=0; ((F>10)) && F=10
BC=$(_pc "$PCT")
BAR=""; for((i=0;i<F;i++)); do BAR+='█'; done; for((i=F;i<10;i++)); do BAR+='░'; done
((CTX>=1000000)) && CL="$((CTX/1000000))M" || CL="$((CTX/1000))K"

if ((DUR>=3600000)); then DS="$((DUR/3600000))h$((DUR/60000%60))m"
elif ((DUR>=60000)); then DS="$((DUR/60000))m$((DUR/1000%60))s"
else DS="$((DUR/1000))s"; fi

GC="/tmp/claude-sl-git-${DIR//[^a-zA-Z0-9]/_}"
if _stale "$GC" 5; then
  if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _BR=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
    _FC=0 _AD=0 _DL=0
    while IFS=$'\t' read -r a d _; do
      [[ "$a" =~ ^[0-9]+$ ]] && ((_FC++,_AD+=a,_DL+=d))
    done < <(git -C "$DIR" --no-optional-locks diff HEAD --numstat 2>/dev/null)
    _TMP=$(mktemp /tmp/claude-sl-g-XXXXXX)
    echo "${_BR}|${_FC}|${_AD}|${_DL}" > "$_TMP" && mv "$_TMP" "$GC"
  else
    echo "|||" > "$GC"
  fi
fi
IFS='|' read -r BR FC AD DL < "$GC" 2>/dev/null
GIT=""
if [ -n "$BR" ]; then
  ((${#BR}>35)) && BR="${BR:0:35}…"
  GS=""; ((FC>0)) 2>/dev/null && GS=" ${FC}f ${G}+${AD}${N} ${R}-${DL}${N}"
  GIT=" | ${BR}${GS}"
fi

SD="${DIR/#$HOME/~}"
if [[ "$SD" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
  SD="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  ((${#SD}>35)) && SD="${SD:0:35}…"
elif ((${#SD}>45)); then
  SD="…${SD: -44}"
fi

# Usage data: prefer stdin rate_limits (CC >=2.1.80), fall back to API polling
SHOW_COST=0
if [[ "$HAS_RL" == "1" ]]; then
  # Stdin path: real-time, no network. U5/U7 already set by jq read above.
  # Guard: resets_at=0 means field missing, leave RM empty so _pace/_rc skip it
  RM5=""; ((R5>0)) && { RM5=$(( (R5 - NOW) / 60 )); ((RM5<0)) && RM5=0; }
  RM7=""; ((R7>0)) && { RM7=$(( (R7 - NOW) / 60 )); ((RM7<0)) && RM7=0; }
  XO=0 XU=0 XL=0
else
  # ── API fallback (remove when CC <2.1.80 no longer supported) ──
  UC="/tmp/claude-sl-usage" UL="/tmp/claude-sl-usage.lock"

  _get_token() {
    [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { echo "$CLAUDE_CODE_OAUTH_TOKEN"; return; }
    local b=""
    command -v security >/dev/null && \
      b=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    [ -z "$b" ] && [ -f ~/.claude/.credentials.json ] && b=$(< ~/.claude/.credentials.json)
    [ -z "$b" ] && command -v secret-tool >/dev/null && \
      b=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
    [ -n "$b" ] && jq -r '.claudeAiOauth.accessToken//empty' <<< "$b" 2>/dev/null
  }

  _fetch_usage() {
    (
      trap 'rm -f "$UL"' EXIT
      TK=$(_get_token); [ -z "$TK" ] && return
      RESP=$(curl -s --max-time 3 \
        -H "Authorization: Bearer $TK" -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
      IFS=$'\t' read -r F5 S7 EX EU EL RM5 RM7 < <(jq -r '
        def rmins: if . and . != "" then (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - (now|floor) | ./60|floor | if .<0 then 0 else . end else null end;
        [(.five_hour.utilization|floor),(.seven_day.utilization|floor),
          (if .extra_usage.is_enabled then 1 else 0 end),
          (.extra_usage.used_credits//0|floor),(.extra_usage.monthly_limit//0|floor),
          (.five_hour.resets_at|rmins//""),(.seven_day.resets_at|rmins//"")]|@tsv' \
        <<< "$RESP" 2>/dev/null) || { [ ! -f "$UC" ] || [[ $(head -c2 "$UC") == -- ]] && echo "--|--|0|0|0||" > "$UC"; touch "$UC"; return; }
      TMP=$(mktemp /tmp/claude-sl-u-XXXXXX)
      echo "${F5}|${S7}|${EX}|${EU}|${EL}|${RM5}|${RM7}" > "$TMP" && mv "$TMP" "$UC"
    ) &
  }

  if _stale "$UC" 300; then
    if (set -o noclobber; echo $$ > "$UL") 2>/dev/null; then
      _fetch_usage
    elif [ -f "$UL" ] && _stale "$UL" 10; then
      rm -f "$UL"; (set -o noclobber; echo $$ > "$UL") 2>/dev/null && _fetch_usage
    fi
  fi

  U5="--" U7="--" XO=0 XU=0 XL=0 RM5="" RM7=""
  [ -f "$UC" ] && IFS='|' read -r U5 U7 XO XU XL RM5 RM7 < "$UC"
  U5=${U5%%.*} U7=${U7%%.*} XU=${XU%%.*} XL=${XL%%.*}
  if [[ "$RM5" =~ ^[0-9]+$ ]] && [ -f "$UC" ]; then
    _CA=$((NOW - $(stat -f%m "$UC" 2>/dev/null || stat -c%Y "$UC" 2>/dev/null || echo $NOW)))
    RM5=$(( RM5 - _CA/60 )); ((RM5<0)) && RM5=0
    [[ "$RM7" =~ ^[0-9]+$ ]] && { RM7=$(( RM7 - _CA/60 )); ((RM7<0)) && RM7=0; }
  fi
  [ ! -f "$UC" ] && SHOW_COST=1
  # ── End API fallback ──
fi

_uf() {
  [[ ! "${1:---}" =~ ^[0-9]+$ ]] && { printf "%s" "${1:---}"; return; }
  printf "$(_pc $1)%d%%${N}" $((100 - $1))
}

# Pace delta: positive = ahead of expected consumption (green), negative = over pace (red); suppress within +-10%
_pace() {
  local used="$1" rmin="$2" win="$3"
  [[ "$used" =~ ^[0-9]+$ ]] && [[ "$rmin" =~ ^[0-9]+$ ]] || return
  ((rmin <= win)) || return
  local elapsed=$((win - rmin))
  local exp=$((elapsed * 100 / win))
  local d=$((exp - used))
  ((d > 10)) && printf " ${G}+%d%%${N}" "$d"
  ((d < -10)) && printf " ${R}%d%%${N}" "$d"
}

# Reset countdown: >=1h show hours, <1h show minutes, >=24h show days
_rc() {
  [[ "$1" =~ ^[0-9]+$ ]] || return
  local m=$1; ((m>=1440)) && { printf " ${D}(%dd)${N}" $((m/1440)); return; }
  ((m>=60)) && { printf " ${D}(%dh)${N}" $((m/60)); return; }
  printf " ${D}(%dm)${N}" "$m"
}
L2="${BC}${BAR}${N} ${PCT}% of ${CL}"
L2+=" | 5h: $(_uf "$U5")$(_pace "$U5" "$RM5" 300)$(_rc "$RM5")"
L2+=" | 7d: $(_uf "$U7")$(_pace "$U7" "$RM7" 10080)$(_rc "$RM7")"
# Session cost: only for confirmed API users (no rate_limits + no OAuth cache)
if [[ "$SHOW_COST" == "1" ]]; then
  printf -v _CS "\$%.2f" "$COST" 2>/dev/null
  [[ "$_CS" != "\$0.00" ]] && L2+=" | $_CS"
fi
L2+=" | ${D}${DS}${N}"

echo -e "${C}[${MODEL} ${EF}]${N} ${SD}${GIT}"
echo -e "$L2"
