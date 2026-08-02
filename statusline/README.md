# Statusline

Model, context-window usage (color-coded), directory + git branch, session duration, effort level, and both rate-limit windows — each with the actual date/time it resets, not just a percentage.

```
Sonnet 5 │ Context Window: 34% │ claude-harness (main*) │ ⏱ 1h12m │ ● high

current ●●●●○○○○○○  34% ⟳ resets in - 2 hrs 3 mins
weekly  ●●○○○○○○○○  28% ⟳ resets in - 5 days 3 hrs
```

## Setup

**Requires:** `bash` + [`jq`](https://jqlang.org/). On Windows this runs through Git Bash — see [Claude Code's Windows statusline notes](https://code.claude.com/docs/en/statusline#windows-configuration) if `jq` isn't already on `PATH`. **If `jq` is missing, the script now prints a one-line error and exits instead of running** (found 2026-08-02: it used to silently continue with empty variables, producing a statusline that looked like real data — e.g. "Context Window: 0%" — instead of an obvious error).

To fix on Windows: `winget install jqlang.jq`. Note this doesn't reliably put `jq` on `PATH` — confirmed 2026-08-02 on a machine where the install succeeded but neither the User nor Machine `PATH` registry value ever gained an entry, so restarting the terminal (or Claude Code itself) changed nothing. The script now also searches `%LOCALAPPDATA%\Microsoft\WinGet\Packages\jqlang.jq_*\jq.exe` directly and uses it if `PATH` resolution fails, so a plain `winget install` is enough even when PATH doesn't get updated. If `jq` was installed some other way (scoop, choco, manual), make sure it's actually on `PATH` — that fallback only covers the winget package layout.

1. Copy `statusline.sh` to `~/.claude/statusline.sh` (or any path you prefer).
2. `chmod +x ~/.claude/statusline.sh`
3. Add to `~/.claude/settings.json` (create the file if it doesn't exist):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh",
       "padding": 0,
       "refreshInterval": 60
     }
   }
   ```

   Use forward slashes in the path even on Windows — Git Bash treats unquoted backslashes as escape characters and the command fails silently otherwise.

   `refreshInterval` re-runs the script every 60s regardless of activity, so the rate-limit countdowns keep ticking down while you're idle instead of freezing at whatever they were on the last message/compact/permission-change event. Local-only, no API or token cost — matches the script's own 60s API-fallback cache window.

That's it — Claude Code reloads settings automatically; the statusline appears on your next interaction.

## Notes

- **Rate-limit resets** show as a countdown (`⟳ resets in - 2 hrs 3 mins`, or `resets in - 5 days 3 hrs` once the weekly window is more than a day out) — `format_time_until()` computes it directly from `rate_limits.*.resets_at`, which Claude Code sends as a raw Unix epoch integer, not an ISO string. The glyph is dim (a subtle separator); "resets in" and the duration are full brightness for readability.
- **Falls back to a direct API call** (cached 60s in `/tmp/claude/`) if Claude Code's stdin payload doesn't include `rate_limits` for your version — reads the OAuth token from macOS Keychain, `libsecret`, or `~/.claude/.credentials.json`, whichever resolves first.
- **Caveman badge** (`[CAVEMAN:ULTRA]` in the example above) is optional and inert unless `~/.claude/.caveman-active` exists — safe to ignore if you don't use that convention.
- Colors: green under 50%, yellow 50-69%, red 70%+ — applies to context window and both rate-limit bars alike.
