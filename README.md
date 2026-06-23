````markdown
# Spotify plugin for Claude Code

Show the now-playing Spotify track in your statusline and control playback from Claude Code. **macOS only** (uses AppleScript), no login required. Requires the Spotify desktop app and `jq`.

## Install

```
/plugin marketplace add <github-user>/claude-spotify
/plugin install spotify
```

## Control

```
/spotify status                              # what's playing
/spotify next                                # next track
/spotify prev                                # previous track
/spotify toggle                              # play / pause
/spotify play spotify:playlist:37i9dQ...     # play a playlist or track by URI
/spotify vol 40                              # set volume 0–100
/spotify mode focus                          # play a named mode (see config) + set its volume
```

To get a playlist/track URI: in Spotify, right-click → Share → Copy Spotify URI.

> Play-by-name / search ("play some chill music") needs the Spotify Web API and is not in this version. Play by URI or by a named mode instead.

## Modes

Copy `spotify.example.json` to `~/.claude/spotify.json` and edit. Each mode has a playlist/track `uri`, optional `volume`, `emoji`, and `color` (red/green/yellow/blue/magenta/cyan/grey). `/spotify mode <name>` plays it and marks it active; the statusline then uses that mode's emoji/color.

## Statusline

Plugins can't set the statusline automatically — add it to your `settings.json` once.

**If you don't have a statusline yet**, this shows the directory plus now-playing:

```json
"statusLine": {
  "type": "command",
  "command": "printf '%s ' \"$(basename \"$(jq -r .workspace.current_dir)\")\"; bash \"${CLAUDE_PLUGIN_ROOT}/bin/spotify-status.sh\""
}
```

**If you already have a statusline**, call the segment from your own script and append its output:

```bash
spotify=$(bash "${CLAUDE_PLUGIN_ROOT}/bin/spotify-status.sh")
[ -n "$spotify" ] && printf '  %s' "$spotify"
```

If `${CLAUDE_PLUGIN_ROOT}` doesn't expand in your statusline context, use the absolute install path printed by `/plugin` (e.g. `~/.claude/plugins/cache/<marketplace>/spotify/<version>/bin/spotify-status.sh`).

## Scope

Phase 1: AppleScript, macOS, no auth. Later: Spotify Web API (search, recommendations, queue, cross-device), MCP server for conversational control.
````
