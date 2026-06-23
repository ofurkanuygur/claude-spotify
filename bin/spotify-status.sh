#!/bin/bash
# Statusline segment: now-playing + mode-based color. Prints nothing if Spotify closed/stopped.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/spotify-lib.sh"
CONFIG="$(spotify_config)"

[ "$(osascript -e 'tell application "System Events" to (exists process "Spotify")' 2>/dev/null)" = "true" ] || exit 0

out=$(osascript 2>/dev/null <<'OSA'
tell application "Spotify"
  set s to player state as string
  if s is "stopped" then return "stopped"
  return s & tab & artist of current track & tab & name of current track
end tell
OSA
)
[ -z "$out" ] && exit 0
state="${out%%$'\t'*}"
[ "$state" = "stopped" ] && exit 0
rest="${out#*$'\t'}"
artist="${rest%%$'\t'*}"
track="${rest#*$'\t'}"

IFS=$'\t' read -r emoji color < <(appearance "$state" "$CONFIG")
printf '\033[%sm%s %s – %s\033[0m' "$color" "$emoji" "$artist" "$track"
