#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# Found by testing (2026-08-02): this used to fall back to one developer's
# hardcoded WinGet install path, which only ever worked on that one machine.
# On any other machine without jq on PATH, every jq call below silently fails
# ("jq: command not found" to stderr) and the script keeps going with empty
# variables -- producing a statusline that LOOKS like real data ("Context
# Window: 0%") but is actually just failed-parse zeros. That's worse than an
# explicit error: 0% reads as a measurement, not as "unknown." Fail loud and
# short instead.
#
# Found by testing (2026-08-02, second pass): `winget install jq` does not
# reliably register PATH at all -- not a stale-shell caching issue, the User
# and Machine PATH registry values never gained an entry, and winget's own
# Links shim dir was empty. "Restart your terminal" does nothing in that
# case. So before giving up, glob every user's WinGet package dir for jq.exe
# and use it directly if found -- this covers any machine, not just one.
if ! command -v jq >/dev/null 2>&1; then
    # $LOCALAPPDATA is Windows-style (C:\Users\...) -- useless as a bash glob/find
    # root directly. Convert with cygpath (ships with Git for Windows, in
    # /usr/bin, so it survives a scrubbed PATH). Don't assume $HOME is
    # POSIX-style either -- Claude Code spawns this as a non-login shell, and
    # on machines with a redirected/AzureAD profile HOME can come through
    # Windows-style too, so fall back to it only if cygpath is unavailable.
    jq_base=$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)
    [ -z "$jq_base" ] && jq_base="$HOME/AppData/Local"
    # `set -f` above disables globbing, so a `*` pattern here would pass through
    # to find literally instead of expanding -- use -iname, not a glob, to search.
    jq_fallback=$(find "$jq_base/Microsoft/WinGet/Packages" -maxdepth 1 -iname 'jqlang.jq_*' -exec test -x '{}/jq.exe' \; -print 2>/dev/null | head -n1)
    [ -n "$jq_fallback" ] && jq_fallback="$jq_fallback/jq.exe"
    if [ -n "$jq_fallback" ] && [ -x "$jq_fallback" ]; then
        jq() { "$jq_fallback" "$@"; }
    else
        printf "claude-harness statusline: jq not found on PATH — see statusline/README.md"
        exit 0
    fi
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
# Everything interpolated into the final `printf "%b"` that comes from
# outside this script -- the stdin payload, the checked-out branch name, the
# caveman flag file -- goes through this first. `%b` expands backslash
# escapes, so a branch named `\033[2J` or a model display name carrying a raw
# ESC byte would otherwise paint arbitrary escape sequences into the user's
# terminal (title rewriting, screen clearing, hidden text). Backslashes become
# forward slashes rather than being dropped: on Windows the payload's cwd is
# backslash-separated, and deleting them would silently glue path components
# together in the directory field.
sanitize_text() {
    printf '%s' "$1" | tr -d '\000-\037\177' | tr '\\' '/'
}

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 70 ]; then printf "$red"
    elif [ "$pct" -ge 50 ]; then printf "$yellow"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_time_until() {
    local epoch=$1
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local now delta
    now=$(date +%s)
    delta=$(( epoch - now ))
    [ "$delta" -lt 0 ] && delta=0

    local days=$(( delta / 86400 ))
    local hours=$(( (delta % 86400) / 3600 ))
    local mins=$(( (delta % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        printf "%d day%s %d hr%s" "$days" "$([ "$days" -ne 1 ] && echo s)" "$hours" "$([ "$hours" -ne 1 ] && echo s)"
    elif [ "$hours" -gt 0 ]; then
        printf "%d hr%s %d min%s" "$hours" "$([ "$hours" -ne 1 ] && echo s)" "$mins" "$([ "$mins" -ne 1 ] && echo s)"
    else
        printf "%d min%s" "$mins" "$([ "$mins" -ne 1 ] && echo s)"
    fi
}

iso_to_epoch() {
    local iso_str="$1"

    # Claude Code sends resets_at as a plain Unix epoch integer, not ISO —
    # pass it straight through instead of feeding it to date parsing below.
    if [[ "$iso_str" =~ ^[0-9]+$ ]]; then
        echo "$iso_str"
        return 0
    fi

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# ── Caveman mode badge — only shown when the flag file exists and is set ──
caveman_badge=""
caveman_flag="$HOME/.claude/.caveman-active"
if [ -f "$caveman_flag" ]; then
    caveman_mode=$(cat "$caveman_flag" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$caveman_mode" ]; then
        caveman_label=$(sanitize_text "$caveman_mode" | tr '[:lower:]' '[:upper:]')
        caveman_badge="${magenta}[CAVEMAN:${caveman_label}]${reset}"
    fi
fi

# ── Extract JSON data (single jq call — each invocation costs real time on Windows) ──
IFS=$'\t' read -r model_name size input_tokens cache_create cache_read cwd session_start <<< "$(echo "$input" | jq -r '[
    (.model.display_name // "Claude"),
    (.context_window.context_window_size // 200000),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.cwd // ""),
    (.session.start_time // "")
] | @tsv')"

[ "$size" -eq 0 ] 2>/dev/null && size=200000
current=$(( input_tokens + cache_create + cache_read ))

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

effort="default"
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    effort=$(sanitize_text "$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)")
fi

# ── LINE 1: Model │ Caveman │ Context % │ Directory (branch) │ Session │ Effort ──
pct_color=$(color_for_pct "$pct_used")
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
model_name=$(sanitize_text "$model_name")
dirname=$(sanitize_text "$(basename "$cwd")")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(sanitize_text "$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)")
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

session_duration=""
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2>/dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
    skip_perms="⚡  "
fi

line1="${blue}${model_name}${reset}"
if [ -n "$caveman_badge" ]; then
    line1+="${sep}"
    line1+="${caveman_badge}"
fi
line1+="${sep}"
line1+="${pct_color}Context Window: ${pct_used}%${reset}"
line1+="${sep}"
line1+="${skip_perms}${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
fi
if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi
line1+="${sep}"
case "$effort" in
    high)   line1+="${magenta}● ${effort}${reset}" ;;
    medium) line1+="${dim}◑ ${effort}${reset}" ;;
    low)    line1+="${dim}◔ ${effort}${reset}" ;;
    *)      line1+="${dim}◑ ${effort}${reset}" ;;
esac

# ── Rate limits from stdin (primary) ───────────────────
has_stdin_rates=false
five_hour_pct=""
five_hour_reset_epoch=""
seven_day_pct=""
seven_day_reset_epoch=""

IFS=$'\t' read -r stdin_five_pct five_hour_reset_iso stdin_seven_pct seven_day_reset_iso <<< "$(echo "$input" | jq -r '[
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
] | @tsv')"

if [ -n "$stdin_five_pct" ]; then
    has_stdin_rates=true
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct")
    five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso")
    seven_day_pct=$(printf "%.0f" "$stdin_seven_pct" 2>/dev/null)
    seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso")
fi

# ── Fallback: API call (cached) ────────────────────────
# Per-user cache dir, 0700, NOT a shared world-writable path. The previous
# location (/tmp/claude) is attacker-plantable on any multi-user machine: a
# local attacker who creates /tmp/claude first owns the directory, so
# `> "$cache_file"` follows a symlink they place there (arbitrary file
# overwrite as this user) and whatever JSON they leave behind is what the
# statusline renders.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-harness"
cache_file="$cache_dir/statusline-usage-cache.json"
cache_max_age=60
mkdir -m 700 -p "$cache_dir" 2>/dev/null
# Never read through / write through a symlink left in place of the cache.
[ -L "$cache_file" ] && rm -f "$cache_file"

usage_data=""
extra_enabled="false"

if ! $has_stdin_rates; then
    needs_refresh=true

    if [ -f "$cache_file" ]; then
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            needs_refresh=false
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if $needs_refresh; then
        token=""
        if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
            token="$CLAUDE_CODE_OAUTH_TOKEN"
        elif command -v security >/dev/null 2>&1; then
            blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            creds_file="${HOME}/.claude/.credentials.json"
            if [ -f "$creds_file" ]; then
                token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            if command -v secret-tool >/dev/null 2>&1; then
                blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
                if [ -n "$blob" ]; then
                    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                fi
            fi
        fi

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            # The OAuth token goes in via a config file on stdin, never on the
            # command line: argv is world-readable through `ps` on Linux and
            # macOS, so `-H "Authorization: Bearer $token"` leaks the token to
            # every other local user for the lifetime of the request.
            response=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: claude-code/2.1.34" \
                --config - \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                usage_data="$response"
                echo "$response" > "$cache_file"
            fi
        fi
        if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
        five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
        five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso")
        seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso")

        extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    fi
else
    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
            extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
        fi
    fi
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_time_until "$five_hour_reset_epoch")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")
    five_hour_pct_fmt=$(printf "%3d" "$five_hour_pct")

    rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}resets in - ${five_hour_reset}${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_time_until "$seven_day_reset_epoch")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")
    seven_day_pct_fmt=$(printf "%3d" "$seven_day_pct")

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}resets in - ${seven_day_reset}${reset}"
fi

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_pct_color=$(color_for_pct "$extra_pct")

    extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -z "$extra_reset" ]; then
        extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
