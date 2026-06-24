#!/bin/bash
# Spotify control via AppleScript (macOS). No auth. Never launches Spotify.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/spotify-lib.sh"
CONFIG="$(spotify_config)"

spotify_running() {
  [ "$(osascript -e 'tell application "System Events" to (exists process "Spotify")' 2>/dev/null)" = "true" ]
}
osa() { osascript -e "tell application \"Spotify\" to $1" 2>/dev/null; }
require_running() { spotify_running || { echo "Spotify çalışmıyor. Önce Spotify'ı aç." >&2; exit 1; }; }

now_playing() {
  spotify_running || { echo "Spotify kapalı."; return 0; }
  local state; state=$(osa 'player state as string')
  case "$state" in
    playing|paused) echo "$state: $(osa 'artist of current track') – $(osa 'name of current track')" ;;
    *) echo "Çalan bir şey yok." ;;
  esac
}

cmd="${1:-status}"; [ $# -gt 0 ] && shift

case "$cmd" in
  next)   require_running; osa 'next track' >/dev/null; now_playing ;;
  prev)   require_running; osa 'previous track' >/dev/null; now_playing ;;
  toggle) require_running; osa 'playpause' >/dev/null; now_playing ;;
  play)
    require_running
    [ -n "${1:-}" ] || { echo "Kullanım: /spotify play <spotify:uri>" >&2; exit 1; }
    osa "play track \"$(applescript_escape "$1")\"" >/dev/null
    # ad-hoc play leaves any mode → clear active so the statusline falls back to 🎵
    [ -f "$CONFIG" ] && { tmp=$(mktemp); jq '.active = null' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"; }
    now_playing ;;
  vol)
    require_running
    { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ]; } || { echo "Kullanım: /spotify vol <0-100>" >&2; exit 1; }
    osa "set sound volume to $1" >/dev/null; echo "Ses: $1" ;;
  mode)
    require_running
    name="${1:-}"
    [ -n "$name" ] || { echo "Kullanım: /spotify mode <ad>" >&2; exit 1; }
    if ! resolved=$(resolve_mode "$CONFIG" "$name"); then
      echo "Bilinmeyen mod: $name. Tanımlılar: $(list_modes "$CONFIG")" >&2; exit 1
    fi
    IFS=$'\t' read -r uri vol _emoji _color <<<"$resolved"
    osa "play track \"$(applescript_escape "$uri")\"" >/dev/null
    { [[ "$vol" =~ ^[0-9]+$ ]] && [ "$vol" -le 100 ]; } && osa "set sound volume to $vol" >/dev/null
    tmp=$(mktemp); jq --arg m "$name" '.active = $m' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    echo "Mod: $name"; now_playing ;;
  resolve) resolve_mode "$CONFIG" "${1:-}" ;;
  status)  now_playing ;;
  *) echo "Bilinmeyen komut: $cmd (next|prev|toggle|play|vol|mode|status)" >&2; exit 1 ;;
esac
