#!/bin/bash
# Pure helpers for the Spotify plugin. No osascript, no side effects on Spotify.
# Sourced by spotify.sh and spotify-status.sh; exercised directly by tests.

spotify_config() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spotify.json"; }

# Escape a string for safe interpolation inside an AppleScript double-quoted
# literal. Without this, a URI containing a double-quote can break out of the
# literal and inject AppleScript (e.g. `do shell script`) → RCE.
applescript_escape() {
  local s=$1
  s=${s//\\/\\\\}   # backslash first
  s=${s//\"/\\\"}   # then double-quote
  printf '%s' "$s"
}

# Map a color name to an ANSI SGR code. Unknown/empty → 35 (magenta).
spotify_color_code() {
  case "$1" in
    red) echo 31;; green) echo 32;; yellow) echo 33;;
    blue) echo 34;; magenta) echo 35;; cyan) echo 36;;
    grey|gray) echo 90;; *) echo 35;;
  esac
}

# resolve_mode <config> <name> → "uri<TAB>volume<TAB>emoji<TAB>color"; returns 1 if missing/unknown.
resolve_mode() {
  local config="$1" name="$2" uri vol emoji color
  [ -f "$config" ] || return 1
  uri=$(jq -r --arg m "$name" '.modes[$m].uri // empty' "$config" 2>/dev/null)
  [ -n "$uri" ] || return 1
  vol=$(jq -r --arg m "$name" '.modes[$m].volume // empty' "$config" 2>/dev/null)
  emoji=$(jq -r --arg m "$name" '.modes[$m].emoji // "🎵"' "$config" 2>/dev/null)
  color=$(jq -r --arg m "$name" '.modes[$m].color // empty' "$config" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$uri" "$vol" "$emoji" "$color"
}

# list_modes <config> → comma-separated mode names (empty if none).
list_modes() {
  local config="$1"
  [ -f "$config" ] || return 0
  jq -r '(.modes // {}) | keys_unsorted | join(", ")' "$config" 2>/dev/null
}

# appearance <state> <config> → "emoji<TAB>colorcode".
# paused → dim grey ⏸; playing → active mode's emoji/color if set, else 🎵/35.
appearance() {
  local state="$1" config="$2" active emoji color
  if [ "$state" = "paused" ]; then printf '⏸\t90\n'; return 0; fi
  active=""
  [ -f "$config" ] && active=$(jq -r '.active // empty' "$config" 2>/dev/null)
  if [ -n "$active" ] && [ -f "$config" ]; then
    emoji=$(jq -r --arg m "$active" '.modes[$m].emoji // "🎵"' "$config" 2>/dev/null)
    color=$(jq -r --arg m "$active" '.modes[$m].color // empty' "$config" 2>/dev/null)
    printf '%s\t%s\n' "$emoji" "$(spotify_color_code "$color")"
    return 0
  fi
  printf '🎵\t35\n'
}
