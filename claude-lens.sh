#!/usr/bin/env bash
# Claude Code statusline
# 行1: [模型 ●effort] 目录 | 分支 Nf +A -D
# 行2: ████░░ PCT% of SIZE | 5h: X%↑D | 7d: X% | [extra] | [$cost] | 时长
set -f
input=$(cat)
[ -z "$input" ] && { echo "Claude"; exit 0; }
command -v jq >/dev/null || { echo "Claude [需要jq]"; exit 0; }

# ── 颜色 & 工具 ──
C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m' D='\033[2m' N='\033[0m'
# 百分比→颜色（绿<70 黄70-89 红≥90）
_pc() { (($1>=90)) && printf "$R" || { (($1>=70)) && printf "$Y" || printf "$G"; }; }
NOW=$(date +%s)
_stale() { [ ! -f "$1" ] || [ $((NOW-$(stat -f%m "$1" 2>/dev/null||stat -c%Y "$1" 2>/dev/null||echo 0))) -gt "$2" ]; }

# ── 解析 stdin + settings（单次 jq）──
IFS=$'\t' read -r MODEL DIR PCT CTX DUR COST EFF < <(
  jq -r --slurpfile cfg <(cat ~/.claude/settings.json 2>/dev/null || echo '{}') \
  '[(.model.display_name//"?"),(.workspace.project_dir//"."),
    (.context_window.used_percentage//0|floor),(.context_window.context_window_size//0),
    (.cost.total_duration_ms//0|floor),(.cost.total_cost_usd//0),
    ($cfg[0].effortLevel//"default")]|@tsv' <<< "$input")
case "${EFF:-default}" in high) EF='●';; low) EF='◔';; *) EF='◑';; esac

# ── 上下文进度条 ──
F=$((PCT/10)); ((F<0)) && F=0; ((F>10)) && F=10
BC=$(_pc "$PCT")
BAR=""; for((i=0;i<F;i++)); do BAR+='█'; done; for((i=F;i<10;i++)); do BAR+='░'; done
((CTX>=1000000)) && CL="$((CTX/1000000))M" || CL="$((CTX/1000))K"

# ── 时长 ──
if ((DUR>=3600000)); then DS="$((DUR/3600000))h$((DUR/60000%60))m"
elif ((DUR>=60000)); then DS="$((DUR/60000))m$((DUR/1000%60))s"
else DS="$((DUR/1000))s"; fi

# ── Git（缓存 5s）──
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

# ── 路径缩短 ──
SD="${DIR/#$HOME/~}"
if [[ "$SD" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
  SD="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  ((${#SD}>35)) && SD="${SD:0:35}…"
elif ((${#SD}>45)); then
  SD="…${SD: -44}"
fi

# ── Usage API（缓存 300s，异步 stale-while-revalidate）──
# 缓存格式: 5h|7d|extra_on|extra_used_cents|extra_limit_cents|prev_5h|prev_7d
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
    # 校验+提取合一：必选字段不加 //0，缺失时 jq 自然报错 → read 失败 → touch 延寿
    IFS=$'\t' read -r F5 S7 EX EU EL < <(jq -r \
      '[(.five_hour.utilization|floor),(.seven_day.utilization|floor),
        (if .extra_usage.is_enabled then 1 else 0 end),
        (.extra_usage.used_credits//0|floor),(.extra_usage.monthly_limit//0|floor)]|@tsv' \
      <<< "$RESP" 2>/dev/null) || { [ -f "$UC" ] && touch "$UC"; return; }
    # 读旧值作为 delta 基线
    [ -f "$UC" ] && IFS='|' read -r O5 O7 _ _ _ _ _ < "$UC"
    TMP=$(mktemp /tmp/claude-sl-u-XXXXXX)
    echo "${F5}|${S7}|${EX}|${EU}|${EL}|${O5:-$F5}|${O7:-$S7}" > "$TMP" && mv "$TMP" "$UC"
  ) &
}

if _stale "$UC" 300; then
  if (set -o noclobber; echo $$ > "$UL") 2>/dev/null; then
    _fetch_usage
  elif [ -f "$UL" ] && _stale "$UL" 10; then
    rm -f "$UL"; (set -o noclobber; echo $$ > "$UL") 2>/dev/null && _fetch_usage
  fi
fi

# ── 读取 usage ──
U5="--" U7="--" XO=0 XU=0 XL=0 P5="" P7=""
[ -f "$UC" ] && IFS='|' read -r U5 U7 XO XU XL P5 P7 < "$UC"
# 防御: 缓存值可能含小数（旧版本或 API 差异）
U5=${U5%%.*} U7=${U7%%.*} XU=${XU%%.*} XL=${XL%%.*} P5=${P5%%.*} P7=${P7%%.*}

# usage 格式化: 数值 + 色阶 + delta
_uf() {
  [[ ! "${1:---}" =~ ^[0-9]+$ ]] && { printf "%s" "${1:---}"; return; }
  local d=$(($1-${2:-$1})) ds=""
  ((d>0)) && ds="↑$d"; ((d<0)) && ds="↓${d#-}"
  printf "$(_pc $1)%s%%${N}" "$1${ds}"
}

# ── 组装第 2 行 ──
L2="${BC}${BAR}${N} ${PCT}% of ${CL}"
L2+=" | 5h: $(_uf "$U5" "$P5") | 7d: $(_uf "$U7" "$P7")"
# Extra usage（启用 + 接近限额时才显示，低用量时是噪音）
[ "$XO" = 1 ] && [[ "$U5" =~ ^[0-9]+$ ]] && ((U5>=80)) && \
  printf -v _XS " | \$%d.%02d/\$%d.%02d" $((XU/100)) $((XU%100)) $((XL/100)) $((XL%100)) && L2+="$_XS"
# 会话费用（仅 API 用户: U5 非数字 = 无 OAuth 用量数据）
if [[ ! "$U5" =~ ^[0-9]+$ ]]; then
  printf -v _CS "\$%.2f" "$COST" 2>/dev/null
  [ "$_CS" != "\$0.00" ] && L2+=" | $_CS"
fi
L2+=" | ${D}${DS}${N}"

# ── 输出 ──
echo -e "${C}[${MODEL} ${EF}]${N} ${SD}${GIT}"
echo -e "$L2"
